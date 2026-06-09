/// Model representing the state of a single servo motor.
///
/// Supports both positional (180°) and continuous rotation (360°) servos.
/// For continuous rotation servos, [baseWriteValue] holds the raw write value
/// (90=STOP, <90=CW, >90=CCW) instead of a positional angle.
class ServoState {
  final String name;
  final int minAngle;
  final int maxAngle;
  final bool isContinuous;
  int currentAngle;
  int baseWriteValue;  // For continuous servo: raw value sent to servo (90=stop)

  ServoState({
    required this.name,
    required this.currentAngle,
    this.minAngle = 0,
    this.maxAngle = 180,
    this.isContinuous = false,
    this.baseWriteValue = 90,
  });

  /// Adjust the angle by [step] and clamp within [minAngle, maxAngle].
  /// Returns true if the angle actually changed.
  /// Only used for positional (non-continuous) servos.
  bool adjustAngle(int step) {
    int newAngle = (currentAngle + step).clamp(minAngle, maxAngle);
    if (newAngle != currentAngle) {
      currentAngle = newAngle;
      return true;
    }
    return false;
  }

  /// Build the MQTT payload string: "name:value"
  /// For continuous servos, sends baseWriteValue (speed/direction).
  /// For positional servos, sends currentAngle.
  String toPayload() => isContinuous
      ? '$name:$baseWriteValue'
      : '$name:$currentAngle';
}
