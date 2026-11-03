enum PhoneHold { topForwardHorizontal, tilted, changedHand, pocket, unknown }

class FieldTrialMeasurement {
  FieldTrialMeasurement({
    required this.groundTruthMeters,
    required this.manualSteps,
    required this.detectorEvents,
    required this.strideMeters,
    required this.estimatedMeters,
    this.endpointErrorBeforeQrMeters,
    this.endpointErrorAfterQrMeters,
    this.falseStepsStill,
    this.hold = PhoneHold.unknown,
    this.uncertainObserved,
    this.budgetHeld,
    this.edgeReselected,
  }) {
    for (final n in [
      groundTruthMeters,
      estimatedMeters,
      endpointErrorBeforeQrMeters,
      endpointErrorAfterQrMeters,
    ]) {
      if (n != null && (!n.isFinite || n < 0 || n > 10000)) {
        throw const FormatException(
          'Khoảng cách/sai lệch phải hữu hạn, không âm và tối đa 10000 m.',
        );
      }
    }
    if (!strideMeters.isFinite || strideMeters < .2 || strideMeters > 1.5) {
      throw const FormatException('Chiều dài bước cần 0,2–1,5 m/bước.');
    }
    for (final n in [manualSteps, detectorEvents, falseStepsStill]) {
      if (n != null && (n < 0 || n > 100000)) {
        throw const FormatException(
          'Số bước phải là số nguyên từ 0 đến 100000.',
        );
      }
    }
  }
  final double groundTruthMeters, strideMeters, estimatedMeters;
  final int manualSteps, detectorEvents;
  final double? endpointErrorBeforeQrMeters, endpointErrorAfterQrMeters;
  final int? falseStepsStill;
  final PhoneHold hold;
  final bool? uncertainObserved, budgetHeld, edgeReselected;
  // Distance bias is not a measured physical endpoint error.
  double get distanceBiasMeters => estimatedMeters - groundTruthMeters;
  double? get relativeDistanceError {
    if (groundTruthMeters <= 0) return null;
    final ratio = distanceBiasMeters / groundTruthMeters;
    return ratio.isFinite ? ratio : null;
  }

  int get detectorStepBias => detectorEvents - manualSteps;
  double? get relativeStepError =>
      manualSteps > 0 ? detectorStepBias / manualSteps : null;
  Map<String, Object?> toJson() => {
    'groundTruthMetersUserMeasured': groundTruthMeters,
    'manualStepsUserCounted': manualSteps,
    'detectorEventsObserved': detectorEvents,
    'configuredStrideMeters': strideMeters,
    'estimatedMeters': estimatedMeters,
    'distanceBiasMetersNotEndpointError': distanceBiasMeters,
    'relativeDistanceError': relativeDistanceError,
    'detectorStepBias': detectorStepBias,
    'relativeStepError': relativeStepError,
    'endpointErrorBeforeQrUserMeasured': endpointErrorBeforeQrMeters,
    'endpointErrorAfterQrUserMeasured': endpointErrorAfterQrMeters,
    'falseStepsWhileStillUserObserved': falseStepsStill,
    'phoneHold': hold.name,
    'uncertainObserved': uncertainObserved,
    'budgetHeld': budgetHeld,
    'edgeReselected': edgeReselected,
  };
}
