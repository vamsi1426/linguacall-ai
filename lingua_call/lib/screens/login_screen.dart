import 'package:flutter/material.dart';
import 'package:linguacall/utils/theme.dart';
import 'package:linguacall/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:linguacall/screens/otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool isLoading = false;

  void sendOTP() async {
    final rawInput = _phoneController.text.trim();
    if (rawInput.isEmpty) return;

    // Firebase Phone Auth requires E.164 format: +<country_code><number>
    // If the user doesn't provide '+', default to US (+1) to keep the UI simple.
    final phone = rawInput.startsWith('+') ? rawInput : '+1$rawInput';
    setState(() => isLoading = true);
    
    try {
      await Provider.of<AuthService>(context, listen: false).sendOTP(phone);
      
      Navigator.push(context, MaterialPageRoute(builder: (_) => const OTPScreen()));
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending OTP: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.maps_ugc_rounded, size: 80, color: AppTheme.secondaryColor),
              const SizedBox(height: 30),
              const Text(
                'Welcome to LinguaCall',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter your phone number to continue',
                style: TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 40),
              Container(
                decoration: AppTheme.glassCard,
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          hintText: 'Enter your phone number',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isLoading ? null : sendOTP,
                  child: isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send OTP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
