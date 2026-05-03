import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = false;
  bool _testingServer = false;
  String? _serverStatus; // null = untested, 'ok', 'error'

  // Server
  final _serverCtrl = TextEditingController(text: ServerConfig.address);

  // Login
  final _loginUser = TextEditingController();
  final _loginPass = TextEditingController();

  // Register
  final _regUser = TextEditingController();
  final _regPass = TextEditingController();
  final _regCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // If server is already configured, mark as ok without re-testing
    if (ServerConfig.isConfigured) _serverStatus = 'ok';
  }

  @override
  void dispose() {
    _tab.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _testAndSaveServer() async {
    final addr = _serverCtrl.text.trim();
    if (addr.isEmpty) {
      _showError('Please enter a server address');
      return;
    }
    setState(() { _testingServer = true; _serverStatus = null; });
    await ServerConfig.save(addr);
    try {
      final dio = Dio(BaseOptions(
        baseUrl: ServerConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      await dio.get('/health');
      setState(() { _serverStatus = 'ok'; });
    } catch (_) {
      // Connection failed — still save the address but warn the user
      setState(() { _serverStatus = 'error'; });
      _showError('Cannot reach server — check address and try again');
    } finally {
      setState(() { _testingServer = false; });
    }
  }

  Future<void> _login() async {
    if (!_ensureServer()) return;
    setState(() => _loading = true);
    try {
      await AuthService.login(_loginUser.text.trim(), _loginPass.text);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
    } on DioException catch (e) {
      _showError(e.response?.data['error'] ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!_ensureServer()) return;
    setState(() => _loading = true);
    try {
      await AuthService.register(
        _regUser.text.trim(),
        _regPass.text,
        _regCode.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
    } on DioException catch (e) {
      _showError(e.response?.data['error'] ?? 'Registration failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _ensureServer() {
    if (!ServerConfig.isConfigured) {
      _showError('Please configure a server address first');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),
                  const Icon(Icons.chat_bubble_rounded, size: 64, color: Color(0xFF1A73E8)),
                  const SizedBox(height: 16),
                  const Text('Chat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),

                  // ── Server address ──────────────────────────────────────
                  _serverCard(),
                  const SizedBox(height: 16),

                  // ── Login / Register ────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tab,
                          tabs: const [Tab(text: 'Login'), Tab(text: 'Register')],
                          indicatorColor: const Color(0xFF1A73E8),
                        ),
                        SizedBox(
                          height: 260,
                          child: TabBarView(
                            controller: _tab,
                            children: [_loginForm(), _registerForm()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serverCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _serverStatus == 'ok'
              ? Colors.green.withOpacity(0.6)
              : _serverStatus == 'error'
                  ? Colors.red.withOpacity(0.6)
                  : Colors.white12,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              const Text('Server', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const Spacer(),
              if (_serverStatus == 'ok')
                Row(children: const [
                  Icon(Icons.check_circle, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Connected', style: TextStyle(color: Colors.green, fontSize: 12)),
                ]),
              if (_serverStatus == 'error')
                Row(children: const [
                  Icon(Icons.error_outline, size: 14, color: Colors.red),
                  SizedBox(width: 4),
                  Text('Unreachable', style: TextStyle(color: Colors.red, fontSize: 12)),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serverCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) => _testAndSaveServer(),
                  decoration: InputDecoration(
                    hintText: '192.168.1.10:8080  or  chat.example.com',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: _testingServer ? null : _testAndSaveServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A3A5A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _testingServer
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Test', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter IP:port or domain. http:// is added automatically.',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _loginForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _field(_loginUser, 'Username', Icons.person),
          const SizedBox(height: 12),
          _field(_loginPass, 'Password', Icons.lock, obscure: true),
          const Spacer(),
          _button('Login', _login),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _field(_regUser, 'Username', Icons.person),
          const SizedBox(height: 8),
          _field(_regPass, 'Password (min 6)', Icons.lock, obscure: true),
          const SizedBox(height: 8),
          _field(_regCode, 'Invite Code', Icons.vpn_key),
          const Spacer(),
          _button('Register', _register),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A73E8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
