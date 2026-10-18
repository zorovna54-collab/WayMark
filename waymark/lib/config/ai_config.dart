import'package:flutter/foundation.dart';

class AIConfig{
  static const String laptopIp ='192.168.1.100';

  static String get baseUrl{
    if(kDebugMode){
      return 'http://127.0.0.1:1234/v1';
    }

    switch(defaultTargetPlatform){
      case TargetPlatform.android:
        return 'http://10.0.2.2:1234/v1';
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return 'http://127.0.0.1:1234/v1';
      case TargetPlatform.iOS:
        return 'http://$laptopIp:1234/v1';
      default:
        return 'http://$laptopIp:1234/v1';
    }
  }
}