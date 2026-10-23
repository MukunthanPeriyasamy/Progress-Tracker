import 'dart:convert';
import 'dart:io';

class TrackerApi {
  TrackerApi({String? baseUrl})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'TRACKER_API_URL',
            defaultValue: 'http://10.0.2.2:8000',
          );
  final String baseUrl;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await client
          .openUrl(body == null ? 'GET' : 'POST', uri)
          .timeout(const Duration(seconds: 8));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw TrackerException(
          data['error'] as String? ?? 'Tracker request failed.',
        );
      }
      return data;
    } on TrackerException {
      rethrow;
    } catch (_) {
      throw TrackerException(
        'Cannot connect to the tracker server. Check that it is running and reachable.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> plan() => request('/api/plan');
  Future<Map<String, dynamic>> day(String date) =>
      request('/api/day?date=$date');
  Future<Map<String, dynamic>> save(Map<String, dynamic> update) =>
      request('/api/update', body: update);
}

class TrackerException implements Exception {
  TrackerException(this.message);
  final String message;
  @override
  String toString() => message;
}
