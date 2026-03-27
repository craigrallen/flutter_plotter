import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../data/providers/floatilla_provider.dart';

class FloatillaAuthScreen extends ConsumerStatefulWidget {
  const FloatillaAuthScreen({super.key});

  @override
  ConsumerState<FloatillaAuthScreen> createState() =>
      _FloatillaAuthScreenState();
}

class _FloatillaAuthScreenState extends ConsumerState<FloatillaAuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Login fields
  final _loginUsernameCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  // Register fields
  final _regUsernameCtrl = TextEditingController();
  final _regVesselCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regPasswordConfirmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _obscureLogin = true;
  bool _obscureReg = true;
  bool _obscureRegConfirm = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginUsernameCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regVesselCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regPasswordConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _loginUsernameCtrl.text.trim();
    final password = _loginPasswordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter username and password');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final ok = await FloatillaService.instance.login(username, password);
      if (!mounted) return;
      if (ok) {
        ref.read(isLoggedInProvider.notifier).state = true;
      } else {
        setState(() => _error = 'Invalid username or password');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error — check server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final username = _regUsernameCtrl.text.trim();
    final vessel = _regVesselCtrl.text.trim();
    final password = _regPasswordCtrl.text;
    final confirm = _regPasswordConfirmCtrl.text;

    if (username.isEmpty || vessel.isEmpty || password.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }
    if (username.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final ok =
          await FloatillaService.instance.register(username, vessel, password);
      if (!mounted) return;
      if (ok) {
        ref.read(isLoggedInProvider.notifier).state = true;
      } else {
        setState(() => _error = 'Username already taken or server error');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error — check server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Log In'), Tab(text: 'Register')],
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(_error!,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LoginTab(
                usernameCtrl: _loginUsernameCtrl,
                passwordCtrl: _loginPasswordCtrl,
                obscure: _obscureLogin,
                onToggleObscure: () =>
                    setState(() => _obscureLogin = !_obscureLogin),
                loading: _loading,
                onSubmit: _login,
              ),
              _RegisterTab(
                usernameCtrl: _regUsernameCtrl,
                vesselCtrl: _regVesselCtrl,
                passwordCtrl: _regPasswordCtrl,
                confirmCtrl: _regPasswordConfirmCtrl,
                obscure: _obscureReg,
                obscureConfirm: _obscureRegConfirm,
                onToggleObscure: () =>
                    setState(() => _obscureReg = !_obscureReg),
                onToggleObscureConfirm: () =>
                    setState(() => _obscureRegConfirm = !_obscureRegConfirm),
                loading: _loading,
                onSubmit: _register,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Login tab ─────────────────────────────────────────────────────────────────

class _LoginTab extends StatelessWidget {
  const _LoginTab({
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.sailing, size: 56, color: Colors.blueAccent),
          const SizedBox(height: 16),
          const Text('Welcome back',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Log in to see your fleet and friends',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 32),
          TextField(
            controller: usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordCtrl,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: onToggleObscure,
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : onSubmit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Log In', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// ── Register tab ──────────────────────────────────────────────────────────────

class _RegisterTab extends StatelessWidget {
  const _RegisterTab({
    required this.usernameCtrl,
    required this.vesselCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscure,
    required this.obscureConfirm,
    required this.onToggleObscure,
    required this.onToggleObscureConfirm,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController usernameCtrl;
  final TextEditingController vesselCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool obscure;
  final bool obscureConfirm;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleObscureConfirm;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.anchor, size: 56, color: Colors.blueAccent),
          const SizedBox(height: 16),
          const Text('Join Floatilla',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Create an account to connect with your fleet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 32),
          TextField(
            controller: usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              helperText: 'Min. 3 characters',
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: vesselCtrl,
            decoration: const InputDecoration(
              labelText: 'Vessel name',
              prefixIcon: Icon(Icons.sailing),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordCtrl,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              helperText: 'Min. 6 characters',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: onToggleObscure,
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirmCtrl,
            obscureText: obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    obscureConfirm ? Icons.visibility : Icons.visibility_off),
                onPressed: onToggleObscureConfirm,
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : onSubmit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create Account', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
