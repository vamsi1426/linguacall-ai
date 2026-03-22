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
  State<DialpadScreen> createState() => DialpadScreenState();
}

class DialpadScreenState extends State<DialpadScreen> {
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
                    } catch (_) {}

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

  Widget _buildButton(String title, String subtitle, double size, double fontSize, double subSize) {
    return InkWell(
      onTap: () => _onKeyPress(title),
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppTheme.cardColor,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.white)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: subSize, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final compact = h < 520 || w < 340;
        final keySize = compact ? 64.0 : 76.0;
        final keyFont = compact ? 22.0 : 26.0;
        final subFont = compact ? 9.0 : 11.0;
        final rowGap = compact ? 8.0 : 12.0;
        final hPad = compact ? 16.0 : 28.0;
        final displaySize = compact ? 28.0 : 34.0;
        final callSize = compact ? 68.0 : 78.0;

        Widget row(List<Widget> children) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children,
            );

        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: hPad,
            right: hPad,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: _onLongPressNumber,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _number.isEmpty ? ' ' : _number,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: displaySize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                row([
                  _buildButton('1', '', keySize, keyFont, subFont),
                  _buildButton('2', 'ABC', keySize, keyFont, subFont),
                  _buildButton('3', 'DEF', keySize, keyFont, subFont),
                ]),
                SizedBox(height: rowGap),
                row([
                  _buildButton('4', 'GHI', keySize, keyFont, subFont),
                  _buildButton('5', 'JKL', keySize, keyFont, subFont),
                  _buildButton('6', 'MNO', keySize, keyFont, subFont),
                ]),
                SizedBox(height: rowGap),
                row([
                  _buildButton('7', 'PQRS', keySize, keyFont, subFont),
                  _buildButton('8', 'TUV', keySize, keyFont, subFont),
                  _buildButton('9', 'WXYZ', keySize, keyFont, subFont),
                ]),
                SizedBox(height: rowGap),
                row([
                  _buildButton('*', '', keySize, keyFont, subFont),
                  _buildButton('0', '+', keySize, keyFont, subFont),
                  _buildButton('#', '', keySize, keyFont, subFont),
                ]),
                SizedBox(height: compact ? 16 : 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(width: callSize),
                    GestureDetector(
                      onTap: _onCall,
                      child: Container(
                        width: callSize,
                        height: callSize,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.greenAccent, blurRadius: 12, spreadRadius: 1),
                          ],
                        ),
                        child: Icon(Icons.call, color: Colors.white, size: callSize * 0.45),
                      ),
                    ),
                    GestureDetector(
                      onTap: _onDelete,
                      onLongPress: () => setState(() => _number = ''),
                      child: SizedBox(
                        width: callSize,
                        height: callSize,
                        child: Icon(Icons.backspace_outlined, color: AppTheme.textMuted, size: callSize * 0.35),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      selected: _callType == CallType.voice,
                      label: const Text('Voice'),
                      onSelected: (_) => setState(() => _callType = CallType.voice),
                    ),
                    ChoiceChip(
                      selected: _callType == CallType.video,
                      label: const Text('Video'),
                      onSelected: (_) => setState(() => _callType = CallType.video),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
