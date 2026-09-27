import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/config/api_config.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';

Dio createDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      // Image uploads need longer send/receive than plain JSON calls.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        // Do not set Content-Type globally — FormData uploads need Dio to
        // generate multipart/form-data; boundary=... itself.
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  return dio;
}

Never throwFromDio(DioException e) {
  final response = e.response;
  if (response != null) {
    throw parseApiError(response.statusCode ?? 0, response.data);
  }

  final message = switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'The server is taking too long. Check Wi‑Fi and that the API is running.',
    DioExceptionType.connectionError =>
      'Cannot reach API at ${ApiConfig.baseUrl}. Is the server running on the same network?',
    DioExceptionType.badCertificate =>
      'Secure connection failed. Check the API HTTPS certificate.',
    _ => e.message ??
        'Network error. Check your connection and API URL (${ApiConfig.baseUrl}).',
  };

  throw ApiException(
    message: message,
    statusCode: null,
  );
}

Never throwApiResponse(Response<dynamic> r) {
  throw parseApiError(r.statusCode ?? 0, r.data);
}

ApiException parseApiError(int statusCode, dynamic data) {
  final fieldErrors = <String, List<String>>{};
  String message = 'Request failed';

  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    final err = m['errors'];
    if (err is Map) {
      for (final e in err.entries) {
        final v = e.value;
        if (v is List) {
          fieldErrors[e.key] = v.map((x) => x.toString()).toList();
        } else if (v != null) {
          fieldErrors[e.key] = [v.toString()];
        }
      }
    }
    final msg = m['message'];
    if (msg is String && msg.isNotEmpty) {
      message = msg;
    } else if (fieldErrors.isNotEmpty) {
      message = fieldErrors.values.first.first;
    }
  }

  if (statusCode == 401) {
    message = 'Invalid email or password, or session expired.';
  } else if (statusCode == 403) {
    message =
        'You do not have access to this action. Use the correct account type.';
  } else if (statusCode == 404) {
    message = 'Resource not found.';
  } else if (statusCode == 413) {
    message = 'Images are too large for the server. Try smaller photos.';
  } else if (statusCode == 422 && fieldErrors.isEmpty) {
    message = 'Validation failed. Please review your input.';
  } else if (statusCode >= 500) {
    message = 'Could not complete that request. Please try again.';
  }

  return ApiException(
    message: message,
    statusCode: statusCode,
    fieldErrors: fieldErrors,
  );
}

bool isSuccess(Response<dynamic> r) {
  final c = r.statusCode ?? 0;
  return c >= 200 && c < 300;
}
