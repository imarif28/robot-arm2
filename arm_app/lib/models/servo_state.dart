/// Model representing the state of a single servo motor.
///
/// Holds the servo name (used as MQTT payload key), current angle,
/// minimum angle, and maximum angle for validation.
class ServoState {
  final String name;
  final int minAngle;
  final int maxAngle;
  int currentAngle;

  ServoState({
    required this.name,
    required this.currentAngle,
    this.minAngle = 0,
    this.maxAngle = 180,
  });

  /// Adjust the angle by [step] and clamp within [minAngle, maxAngle].
  /// Returns true if the angle actually changed.
  bool adjustAngle(int step) {
    int newAngle = (currentAngle + step).clamp(minAngle, maxAngle);
    if (newAngle != currentAngle) {
      currentAngle = newAngle;
      return true;
    }
    return false;
  }

  /// Build the MQTT payload string: "name:angle"
  String toPayload() => '$name:$currentAngle';
}
