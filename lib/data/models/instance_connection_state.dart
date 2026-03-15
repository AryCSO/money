class InstanceConnectionState {
  final String instanceName;
  final String state;

  const InstanceConnectionState({
    required this.instanceName,
    required this.state,
  });

  bool get isOpen => state.toLowerCase() == 'open';

  factory InstanceConnectionState.fromJson(Map<String, dynamic> json) {
    final instance = (json['instance'] as Map<String, dynamic>? ?? {});

    return InstanceConnectionState(
      instanceName: (instance['instanceName'] ?? '').toString(),
      state: (instance['state'] ?? '').toString(),
    );
  }
}
