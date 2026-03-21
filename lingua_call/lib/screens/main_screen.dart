import 'package:flutter/material.dart';
import 'package:linguacall/utils/theme.dart';
import 'package:linguacall/screens/home_screen.dart';
import 'package:linguacall/screens/dialpad_screen.dart';
import 'package:linguacall/screens/contacts_screen.dart';
import 'package:linguacall/screens/profile_screen.dart';
import 'package:linguacall/screens/call/incoming_call_screen.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:provider/provider.dart';
import 'package:linguacall/services/auth_service.dart';
import 'package:linguacall/services/signaling_service.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late int _currentIndex;
  bool _didConnectSignaling = false;

  late final VoidCallback _authListener;
  late final AuthService _auth;
  late final SignalingService _signaling;
  bool _didWireIncoming = false;

  final List<Widget> _screens = const [
    HomeScreen(),
    DialpadScreen(),
    ContactsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    WidgetsBinding.instance.addObserver(this);

    _auth = context.read<AuthService>();
    _signaling = context.read<SignalingService>();

    _authListener = () {
      final uid = _auth.user?.uid;
      if (uid == null || _didConnectSignaling) return;
      _didConnectSignaling = true;
      _signaling.connectAndRegister(uid);
    };

    _auth.addListener(_authListener);

    // If user already exists, connect immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authListener());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didWireIncoming) return;
      _didWireIncoming = true;
      _signaling.onIncomingCall = (Map<String, dynamic> data) {
        if (!mounted) return;
        final callerUid = data['callerUid'] as String?;
        final type = (data['type'] as String?) ?? 'voice';
        final callType = type == 'video' ? CallType.video : CallType.voice;
        final label = callerUid ?? 'Unknown';
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => IncomingCallScreen(
              fromPhone: label,
              callType: callType,
              callerUid: callerUid,
            ),
          ),
        );
      };
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isOnline = state == AppLifecycleState.resumed;
    _auth.setOnlineStatus(isOnline);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_authListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LinguaCall AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search is not implemented yet.')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menu is not implemented yet.')),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dialpad),
              label: 'Dialpad',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts),
              label: 'Contacts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
