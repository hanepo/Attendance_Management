import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF003c8f);
  static const primaryLight = Color(0xFF5e92f3);
  static const accent = Color(0xFF00BCD4);
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const error = Color(0xFFD32F2F);
  static const success = Color(0xFF388E3C);
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider = Color(0xFFBDBDBD);
}

class AppStrings {
  static const appName = 'Secure Attendance';
  static const roleAdmin = 'admin';
  static const roleUser = 'user';
}

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const adminHome = '/admin/home';
  static const userHome = '/user/home';
  static const createClass = '/admin/create-class';
  static const classDetail = '/admin/class-detail';
  static const createSession = '/admin/create-session';
  static const viewAttendance = '/admin/view-attendance';
  static const joinClass = '/user/join-class';
  static const faceScan = '/user/face-scan';
  static const faceRegister = '/user/face-register';
}
