import 'package:flutter/material.dart';

import 'relay_dashboard_screen.dart';

class GardenControlApp extends StatelessWidget {
  const GardenControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gartensteuerung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RelayDashboardScreen(),
    );
  }
}
