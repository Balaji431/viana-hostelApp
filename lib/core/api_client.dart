import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as origin_http;
import 'api_session.dart';
import 'app_logger.dart';
import '../main.dart';

export 'package:http/http.dart' show Response, Client, StreamedResponse;

class HttpClientWrapper {
  static Map<String, String> _getHeaders(Map<String, String>? customHeaders) {
    final Map<String, String> headers =
        customHeaders != null ? Map.from(customHeaders) : {};

    // Inject logged-in user information if present
    if (ApiSession.currentUserId != null) {
      headers['X-User-Id'] = ApiSession.currentUserId!;
    }
    if (ApiSession.currentUsername != null) {
      headers['X-User-Username'] = ApiSession.currentUsername!;
    }
    if (ApiSession.currentUserRole != null) {
      headers['X-User-Role'] = ApiSession.currentUserRole!;
    }
    if (ApiSession.currentToken != null) {
      headers['Authorization'] = 'Bearer ${ApiSession.currentToken!}';
    }
    return headers;
  }

  static void _handleError(dynamic error) {
    // Silenced global SnackBar popup to avoid disrupting normal handled flow.
    debugPrint("HttpClientWrapper Error: $error");
  }

  static void _handleResponseError(int statusCode) {
    if (statusCode >= 400) {
      // Silenced global SnackBar popup to avoid disrupting normal handled flow.
      debugPrint("HttpClientWrapper Response Error status: $statusCode");
    }
  }

  static Future<origin_http.Response> get(Uri url,
      {Map<String, String>? headers}) async {
    try {
      AppLogger.request("GET $url");
      final response =
          await origin_http.get(url, headers: _getHeaders(headers));
      AppLogger.response("Status: ${response.statusCode} for GET $url");
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      AppLogger.error("GET $url failed: $e");
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      AppLogger.request("POST $url");
      final response = await origin_http.post(url,
          headers: _getHeaders(headers), body: body, encoding: encoding);
      AppLogger.response("Status: ${response.statusCode} for POST $url");
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      AppLogger.error("POST $url failed: $e");
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> put(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      final response = await origin_http.put(url,
          headers: _getHeaders(headers), body: body, encoding: encoding);
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> delete(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      final response = await origin_http.delete(url,
          headers: _getHeaders(headers), body: body, encoding: encoding);
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }
}

// Global functions matching http package for direct top-level access
Future<origin_http.Response> get(Uri url, {Map<String, String>? headers}) =>
    HttpClientWrapper.get(url, headers: headers);

Future<origin_http.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    HttpClientWrapper.post(url,
        headers: headers, body: body, encoding: encoding);

Future<origin_http.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    HttpClientWrapper.put(url,
        headers: headers, body: body, encoding: encoding);

Future<origin_http.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    HttpClientWrapper.delete(url,
        headers: headers, body: body, encoding: encoding);
