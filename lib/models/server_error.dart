import 'dart:convert';

class ServerError implements Exception {
  final String message;
  final int statusCode;
  final Map<String, List<String>>? fieldErrors;

  ServerError({
    required this.message,
    required this.statusCode,
    this.fieldErrors,
  });

  factory ServerError.fromJson(String body, int statusCode) {
    String message = 'Unknown error';
    Map<String, List<String>>? fieldErrors;

    try {
      final data = json.decode(body);
      
      if (data is Map) {
        // High-level detail message
        if (data['detail'] != null) {
          final detail = data['detail'];
          
          if (detail is String) {
            message = detail;
          } else if (detail is List) {
            // FastAPI validation errors (422)
            fieldErrors = {};
            for (var error in detail) {
              if (error is Map && error['loc'] is List && error['msg'] != null) {
                final loc = (error['loc'] as List).last.toString();
                final msg = error['msg'].toString();
                
                if (fieldErrors.containsKey(loc)) {
                  fieldErrors[loc]!.add(msg);
                } else {
                  fieldErrors[loc] = [msg];
                }
              }
            }
            if (fieldErrors.isNotEmpty) {
              message = 'Ошибка валидации полей';
            }
          }
        } else if (data['error'] != null) {
          message = data['error'].toString();
        }
      }
    } catch (_) {
      message = 'Ошибка разбора ответа сервера ($statusCode)';
    }

    return ServerError(
      message: message,
      statusCode: statusCode,
      fieldErrors: fieldErrors,
    );
  }

  @override
  String toString() => message;
}
