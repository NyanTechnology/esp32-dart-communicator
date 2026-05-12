import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/models/provision_result.dart';

void main() {
  group('ProvisionResult', () {
    test('should hold provided values', () {
      final result = ProvisionResult(
        success: true,
        staIp: '192.168.1.100',
        mode: 'STA',
      );

      expect(result.success, isTrue);
      expect(result.staIp, '192.168.1.100');
      expect(result.mode, 'STA');
    });

    test('should allow null staIp and mode', () {
      final result = ProvisionResult(success: false);
      
      expect(result.success, isFalse);
      expect(result.staIp, isNull);
      expect(result.mode, isNull);
    });
  });
}
