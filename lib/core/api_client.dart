import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as origin_http;
import 'api_service.dart';
import '../main.dart';

export 'package:http/http.dart' show Response, Client, StreamedResponse;

class HttpClientWrapper {
  static Map<String, String> _getHeaders(Map<String, String>? customHeaders) {
    final Map<String, String> headers = customHeaders != null ? Map.from(customHeaders) : {};
    
    // Inject logged-in user information if present
    if (ApiService.currentUserId != null) {
      headers['X-User-Id'] = ApiService.currentUserId!;
    }
    if (ApiService.currentUsername != null) {
      headers['X-User-Username'] = ApiService.currentUsername!;
    }
    if (ApiService.currentUserRole != null) {
      headers['X-User-Role'] = ApiService.currentUserRole!;
    }
    return headers;
  }

  static void _handleError(dynamic error) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    String message = "Unable to load data. Please try again.";
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') || 
        errorStr.contains('network') || 
        errorStr.contains('failed host lookup') ||
        errorStr.contains('connection timed out')) {
      message = "No Internet Connection";
    }

    try {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {}
  }

  static void _handleResponseError(int statusCode) {
    if (statusCode >= 400) {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      try {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Unable to load data. Please try again."),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (_) {}
    }
  }

  static Future<origin_http.Response> get(Uri url, {Map<String, String>? headers}) async {
    try {
      final response = await origin_http.get(url, headers: _getHeaders(headers));
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      final response = await origin_http.post(url, headers: _getHeaders(headers), body: body, encoding: encoding);
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      final response = await origin_http.put(url, headers: _getHeaders(headers), body: body, encoding: encoding);
      _handleResponseError(response.statusCode);
      return response;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  static Future<origin_http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    try {
      final response = await origin_http.delete(url, headers: _getHeaders(headers), body: body, encoding: encoding);
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

Future<origin_http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => 
    HttpClientWrapper.post(url, headers: headers, body: body, encoding: encoding);

Future<origin_http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => 
    HttpClientWrapper.put(url, headers: headers, body: body, encoding: encoding);

Future<origin_http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => 
    HttpClientWrapper.delete(url, headers: headers, body: body, encoding: encoding);
