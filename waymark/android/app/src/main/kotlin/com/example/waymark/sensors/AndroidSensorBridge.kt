package com.example.waymark.sensors

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicLong

/**
 * Foreground transport only: no position/distance/travel heading estimation.
 * Control/registration/sink operations run on main. Sensor callbacks copy
 * values on a worker into a bounded queue, retaining the original generation.
 */
class AndroidSensorBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val SCHEMA = 1
        private const val PERMISSION_REQUEST = 9731 // SAF uses 9721/9722.
        private const val CAPACITY = 256
        private val TYPES = linkedMapOf(
            "stepDetector" to Sensor.TYPE_STEP_DETECTOR,
            "stepCounter" to Sensor.TYPE_STEP_COUNTER,
            "rotationVector" to Sensor.TYPE_ROTATION_VECTOR,
            "gameRotationVector" to Sensor.TYPE_GAME_ROTATION_VECTOR,
            "accelerometer" to Sensor.TYPE_ACCELEROMETER,
            "gyroscope" to Sensor.TYPE_GYROSCOPE,
        )
    }

    private val manager = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val main = Handler(Looper.getMainLooper())
    private val sensorThread = lazy { HandlerThread("WayMarkSensors").apply { start() } }
    private val thread by sensorThread
    private val sensorHandler by lazy { Handler(thread.looper) }
    private val control = MethodChannel(messenger, "waymark/sensors/control")
    private val events = EventChannel(messenger, "waymark/sensors/events")
    private var sink: EventChannel.EventSink? = null
    private var permissionReply: MethodChannel.Result? = null
    private var listener: SensorEventListener? = null
    private val registrations = mutableMapOf<String, String>()
    @Volatile private var running = false
    @Volatile private var generation = 0L
    @Volatile private var destroyed = false
    private var lastGeneration = 0L
    private var foreground = false
    private val queue = ArrayDeque<Map<String, Any>>()
    private var drainScheduled = false
    private var dropped = 0L

    init {
        control.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    private fun isStep(kind: String) = kind == "stepDetector" || kind == "stepCounter"
    private fun permission(): String = when {
        Build.VERSION.SDK_INT < 29 -> "notRequired"
        activity.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED -> "granted"
        else -> "denied"
    }

    private fun units(kind: String) = when (kind) {
        "stepDetector", "stepCounter" -> "steps"
        "accelerometer" -> "m/s2"
        "gyroscope" -> "rad/s"
        else -> "unitless"
    }

    private fun frame(kind: String) = when (kind) {
        "rotationVector" -> "androidEastMagneticNorthUp"
        "gameRotationVector" -> "androidRelativeZUp"
        "stepDetector", "stepCounter" -> "none"
        else -> "androidDevice"
    }

    private fun defaultSensor(type: Int): Sensor? =
        try { manager?.getDefaultSensor(type) } catch (_: RuntimeException) { null }

    private fun probe(): Map<String, Any> = mapOf(
        "schemaVersion" to SCHEMA,
        "device" to (Build.MANUFACTURER + " " + Build.MODEL).take(512),
        "androidApi" to Build.VERSION.SDK_INT,
        "permission" to permission(),
        "sensors" to TYPES.map { (kind, type) ->
            val sensor = defaultSensor(type)
            mapOf(
                "kind" to kind, "available" to (sensor != null),
                "name" to (sensor?.name ?: "").take(512),
                "vendor" to (sensor?.vendor ?: "").take(512),
                "version" to (sensor?.version ?: 0).coerceAtLeast(0),
                "maxRange" to (sensor?.maximumRange?.toDouble() ?: 0.0),
                "resolution" to (sensor?.resolution?.toDouble() ?: 0.0),
                "minDelayUs" to (sensor?.minDelay ?: 0),
                "registration" to (registrations[kind] ?: "notRequested"),
            )
        },
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (destroyed) {
            result.error("SENSOR_CLOSED", "Sensor bridge is closed.", null)
            return
        }
        try {
            when (call.method) {
                "probe" -> result.success(probe())
                "clock" -> result.success(mapOf(
                    "schemaVersion" to SCHEMA,
                    "nativeTimestampNs" to SystemClock.elapsedRealtimeNanos(),
                ))
                "requestPermission" -> {
                    if (permission() != "denied") {
                        result.success(mapOf("schemaVersion" to SCHEMA, "permission" to permission()))
                    } else if (!foreground) {
                        result.error("SENSOR_INACTIVE", "Permission requires a foreground user action.", null)
                    } else if (permissionReply != null) {
                        result.error("SENSOR_BUSY", "A permission request is pending.", null)
                    } else {
                        permissionReply = result
                        try {
                            activity.requestPermissions(
                                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), PERMISSION_REQUEST,
                            )
                        } catch (error: RuntimeException) {
                            permissionReply = null
                            throw error
                        }
                    }
                }
                "start" -> start(call, result)
                "stop" -> { stop("stopped", "Listeners stopped."); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: RuntimeException) {
            if (call.method == "start") stop("error", "Sensor registration failed; cleaned up.")
            result.error("SENSOR_ERROR", "Sensor operation failed.", null)
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        require(call.argument<Int>("schemaVersion") == SCHEMA)
        val requestedGeneration = call.argument<Number>("generation")?.toLong() ?: 0L
        val kinds = call.argument<List<String>>("kinds") ?: emptyList()
        val period = call.argument<Int>("samplingPeriodUs") ?: 0
        require(requestedGeneration > lastGeneration && requestedGeneration > 0)
        require(kinds.isNotEmpty() && kinds.size <= TYPES.size && kinds.toSet().size == kinds.size)
        require(kinds.all { TYPES.containsKey(it) } && period in 20_000..1_000_000)
        check(foreground && sink != null)
        stop("stopped", "Replacing previous registration.")
        lastGeneration = requestedGeneration
        generation = requestedGeneration
        val sessionGeneration = generation
        val startTimestamp = SystemClock.elapsedRealtimeNanos()
        val sequence = AtomicLong(0)
        val callback = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (destroyed || !running || generation != sessionGeneration ||
                    event.timestamp < startTimestamp) return
                val kind = TYPES.entries.firstOrNull { it.value == event.sensor.type }?.key ?: return
                if (isStep(kind) && permission() == "denied") {
                    main.post {
                        if (running && generation == sessionGeneration) {
                            stop("error", "Activity permission revoked; listeners stopped.")
                        }
                    }
                    return
                }
                val received = SystemClock.elapsedRealtimeNanos()
                enqueue(mapOf(
                    "type" to "sample", "schemaVersion" to SCHEMA,
                    "generation" to sessionGeneration,
                    "sequence" to sequence.incrementAndGet(),
                    "kind" to kind, "androidType" to event.sensor.type,
                    "sensorTimestampNs" to event.timestamp,
                    "nativeReceiveTimestampNs" to received,
                    "values" to event.values.map { it.toDouble() },
                    "accuracy" to event.accuracy,
                    "units" to units(kind), "referenceFrame" to frame(kind),
                ), sessionGeneration)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                // Every sample carries event.accuracy; do not flood the UI.
            }
        }
        listener = callback
        running = true
        registrations.clear()
        val outcomes = kinds.map { kind ->
            val sensor = defaultSensor(TYPES.getValue(kind))
            val state = when {
                sensor == null -> "unavailable"
                isStep(kind) && permission() == "denied" -> "permissionDenied"
                else -> try {
                    if (manager?.registerListener(callback, sensor, period, 0, sensorHandler) == true)
                        "registered" else "failed"
                } catch (_: SecurityException) {
                    if (isStep(kind) && permission() == "denied") "permissionDenied" else "failed"
                } catch (_: RuntimeException) { "failed" }
            }
            registrations[kind] = state
            mapOf(
                "kind" to kind, "state" to state,
                "reason" to when (state) {
                    "registered" -> ""
                    "unavailable" -> "No default sensor exposed by this device."
                    "permissionDenied" -> "Activity recognition permission denied."
                    else -> "registerListener failed."
                },
            )
        }
        if (registrations.values.none { it == "registered" }) {
            running = false
            manager?.unregisterListener(callback)
            listener = null
        }
        sink?.success(mapOf(
            "type" to "status", "schemaVersion" to SCHEMA,
            "generation" to sessionGeneration, "state" to "registration",
            "message" to "Per-sensor registration results.", "registrations" to outcomes,
        ))
        result.success(mapOf(
            "schemaVersion" to SCHEMA, "generation" to sessionGeneration,
            "permission" to permission(), "registrations" to outcomes,
        ))
    }

    private fun enqueue(sample: Map<String, Any>, sessionGeneration: Long) {
        synchronized(queue) {
            if (!running || destroyed || generation != sessionGeneration) return
            if (queue.size == CAPACITY) { queue.removeFirst(); dropped++ }
            queue.addLast(sample)
            if (!drainScheduled) {
                drainScheduled = true
                main.post(drain)
            }
        }
    }

    private val drain = object : Runnable {
        override fun run() {
            if (destroyed) return
            val batch = mutableListOf<Map<String, Any>>()
            val lost: Long
            synchronized(queue) {
                repeat(minOf(queue.size, 32)) { batch.add(queue.removeFirst()) }
                lost = dropped
                dropped = 0
                drainScheduled = queue.isNotEmpty()
                if (drainScheduled) main.post(this)
            }
            if (!running) return
            if (lost > 0) status("overflow", "Native buffer overflow: $lost samples lost.", generation)
            for (sample in batch) {
                if (running && sample["generation"] == generation) sink?.success(sample)
            }
        }
    }

    private fun status(state: String, message: String, forGeneration: Long) {
        sink?.success(mapOf(
            "type" to "status", "schemaVersion" to SCHEMA,
            "generation" to forGeneration, "state" to state, "message" to message,
        ))
    }

    private fun stop(state: String, message: String) {
        val previousGeneration = generation
        running = false
        listener?.let { manager?.unregisterListener(it) }
        listener = null
        registrations.replaceAll { _, value -> if (value == "registered") "stopped" else value }
        synchronized(queue) {
            queue.clear()
            dropped = 0
            drainScheduled = false
        }
        main.removeCallbacks(drain)
        if (previousGeneration > 0) status(state, message, previousGeneration)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        stop("stopped", "Previous event subscriber replaced.")
        sink = eventSink
        status("listening", "Event channel connected.", 0)
    }

    override fun onCancel(arguments: Any?) {
        stop("stopped", "Event subscription cancelled.")
        sink = null
    }

    fun onResume() { foreground = true } // Never auto-register.
    fun onPause() {
        foreground = false
        stop("paused", "Activity paused; explicit resume required.")
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val reply = permissionReply
        permissionReply = null
        if (permission() == "denied") stop("paused", "Activity permission denied.")
        reply?.success(mapOf("schemaVersion" to SCHEMA, "permission" to permission()))
        return true
    }

    fun dispose() {
        if (destroyed) return
        stop("stopped", "Sensor bridge disposed.")
        destroyed = true
        permissionReply?.error("SENSOR_CLOSED", "Activity closed during permission request.", null)
        permissionReply = null
        sink = null
        control.setMethodCallHandler(null)
        events.setStreamHandler(null)
        if (sensorThread.isInitialized()) {
            sensorHandler.removeCallbacksAndMessages(null)
            thread.quitSafely()
        }
    }
}
