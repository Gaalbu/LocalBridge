abstract final class ApiRoutes {
  static const ping = '/api/v1/ping';
  static const transferRequest = '/api/v1/transfer/request';

  static String upload(String sessionId, String fileId) =>
      '/api/v1/transfer/$sessionId/file/$fileId';

  static String complete(String sessionId) =>
      '/api/v1/transfer/$sessionId/complete';
}
