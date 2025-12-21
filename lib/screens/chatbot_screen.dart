// lib/screens/chatbot_screen.dart
// Bug 7 Fix: Dedicated Chatbot Screen
import 'package:flutter/material.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messages.add({
      'sender': 'bot',
      'text': 'Hello! I\'m your Digital Goods assistant. How can I help you today?',
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': text});
    });

    _controller.clear();

    // Simulate bot response
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _messages.add({'sender': 'bot', 'text': _generateBotResponse(text)});
      });

      // Scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  String _generateBotResponse(String userMessage) {
    final msg = userMessage.toLowerCase();

    if (msg.contains('help') || msg.contains('support')) {
      return 'I can help you with:\n\n'
          '• How to buy/sell assets\n'
          '• QR code verification\n'
          '• Account management\n'
          '• Transaction status\n\n'
          'What would you like to know more about?';
    } else if (msg.contains('buy') || msg.contains('purchase')) {
      return 'To buy an asset:\n\n'
          '1. Browse available assets on the Home screen\n'
          '2. Tap on any asset to view details\n'
          '3. Click "Request to Buy" button\n'
          '4. Wait for seller approval\n'
          '5. Complete the transaction\n\n'
          'Need more help?';
    } else if (msg.contains('sell') || msg.contains('list')) {
      return 'To sell an asset:\n\n'
          '1. Go to "Add Asset" from your dashboard\n'
          '2. Upload images and documents\n'
          '3. Fill in all required details\n'
          '4. Submit for listing\n'
          '5. Wait for buyer requests\n\n'
          'Is there anything else you\'d like to know?';
    } else if (msg.contains('qr') || msg.contains('scan')) {
      return 'QR Code Verification:\n\n'
          '• Each asset has a unique QR code\n'
          '• Scan using the "Scan" tab\n'
          '• Instantly view asset details\n'
          '• Verify authenticity\n\n'
          'Have you tried scanning a QR code yet?';
    } else if (msg.contains('transaction') || msg.contains('status')) {
      return 'Check your transactions:\n\n'
          '• Go to Profile → Transactions\n'
          '• View pending/approved/completed status\n'
          '• Chat with buyer/seller\n'
          '• Track your purchases and sales\n\n'
          'Need help with a specific transaction?';
    } else if (msg.contains('account') || msg.contains('profile')) {
      return 'Manage your account:\n\n'
          '• Update profile photo\n'
          '• Change password via Reset Password\n'
          '• View favorites and notifications\n'
          '• Access settings for preferences\n\n'
          'What would you like to change?';
    } else if (msg.contains('land') || msg.contains('property')) {
      return 'Land Assets:\n\n'
          '• Browse verified land listings\n'
          '• View plot area and location\n'
          '• Check ownership documents\n'
          '• Request fractional ownership\n\n'
          'Looking for a specific area?';
    } else if (msg.contains('electronics') || msg.contains('phone') || msg.contains('device')) {
      return 'Electronics Assets:\n\n'
          '• Authentic electronics verification\n'
          '• Brand and model details\n'
          '• Warranty information\n'
          '• Condition (new/used)\n\n'
          'What device are you interested in?';
    } else if (msg.contains('thank') || msg.contains('bye')) {
      return 'You\'re welcome! Feel free to ask if you need anything else. Have a great day! 😊';
    } else {
      return 'I\'m here to help! You can ask me about:\n\n'
          '• Buying and selling assets\n'
          '• QR code verification\n'
          '• Account management\n'
          '• Transaction tracking\n'
          '• Land and electronics listings\n\n'
          'What would you like to know?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Goods Assistant'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isBot = message['sender'] == 'bot';

                return Align(
                  alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isBot ? Colors.grey[200] : const Color(0xFF0D47A1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message['text'] ?? '',
                      style: TextStyle(
                        color: isBot ? Colors.black : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D47A1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}