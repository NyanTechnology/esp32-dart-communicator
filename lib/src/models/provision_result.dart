class ProvisionResult {
  ProvisionResult({required this.success, this.staIp, this.mode});

  final bool success;
  final String? staIp;
  final String? mode;
}
