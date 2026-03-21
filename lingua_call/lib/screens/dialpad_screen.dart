import 'package:flutter/material.dart';
import 'package:linguacall/utils/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/screens/call/outgoing_call_screen.dart';

class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key});

  @override
  _DialpadScreenState createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _number = '';
  CallType _callType = CallType.voice;

  void _onKeyPress(String val) {
    setState(() {
      _number += val;
    });
  }

  void _onDelete() {
    if (_number.isNotEmpty) {
      setState(() {
        _number = _number.substring(0, _number.length - 1);
      });
    }
  }

  void _onCall() {
    final trimmed = _number.trim();
    if (trimmed.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutgoingCallScreen(
          targetPhone: trimmed,
          callType: _callType,
        ),
      ),
    );
  }

  void _onLongPressNumber() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Options for \$_number', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              Material(
                color: AppTheme.cardColor,
                child: ListTile(
                  leading: const Icon(Icons.copy, color: AppTheme.primaryColor),
                  title: const Text('Copy number'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _number));
                    Navigator.pop(context);
                  },
                ),
              ),
              Material(
                color: AppTheme.cardColor,
                child: ListTile(
                  leading: const Icon(Icons.person_add, color: AppTheme.primaryColor),
                  title: const Text('Save contact'),
                  onTap: () async {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) return;
                    final phone = _number.trim();
                    if (phone.isEmpty) return;

                    final docId = '${uid}_$phone';
                    // Attempt to link the contact to a known user by phone.
                    String contactUid = '';
                    try {
                      final userSnap = await FirebaseFirestore.instance
                          .collection('users')
                          .where('phone', isEqualTo: phone)
                          .limit(1)
                          .get();
                      if (userSnap.docs.isNotEmpty) {
                        contactUid = userSnap.docs.first.id;
                      }
                    } catch (_) {
                      // If query fails (e.g., indexing), we still save the contact.
                    }

                    await FirebaseFirestore.instance.collection('contacts').doc(docId).set(
                      {
                        'ownerUid': uid,
                        'contactUid': contactUid,
                        'phone': phone,
                        'name': 'Contact $phone',
                        'updatedAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contact saved.')),
                    );
                  },
                ),
              ),
              Material(
                color: AppTheme.cardColor,
                child: ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: const Text('Block number'),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Block is not implemented yet.')),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildButton(String title, String subtitle) {
    return InkWell(
      onTap: () => _onKeyPress(title),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: AppTheme.cardColor,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onLongPress: _onLongPressNumber,
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              _number,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildButton('1', ''),
                  _buildButton('2', 'ABC'),
                  _buildButton('3', 'DEF'),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildButton('4', 'GHI'),
                  _buildButton('5', 'JKL'),
                  _buildButton('6', 'MNO'),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildButton('7', 'PQRS'),
                  _buildButton('8', 'TUV'),
                  _buildButton('9', 'WXYZ'),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildButton('*', ''),
                  _buildButton('0', '+'),
                  _buildButton('#', ''),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 80),
              GestureDetector(
                onTap: _onCall,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.greenAccent, blurRadius: 15, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.call, color: Colors.white, size: 36),
                ),
              ),
              GestureDetector(
                onTap: _onDelete,
                onLongPress: () => setState(() => _number = ''),
                child: const SizedBox(
                   width: 80,
                   height: 80,
                   child: Icon(Icons.backspace_outlined, color: AppTheme.textMuted, size: 28),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                selected: _callType == CallType.voice,
                label: const Text('Voice'),
                onSelected: (_) => setState(() => _callType = CallType.voice),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                selected: _callType == CallType.video,
                label: const Text('Video'),
                onSelected: (_) => setState(() => _callType = CallType.video),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
