import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Role _role = Role.warga;
  String _residentId = 'R1';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppColors.teal,
      body: Stack(
        children: [
          // Latar: gradasi di atas, warna panel di bawah, agar panel putih
          // tampak menyambung sampai dasar layar pada layar yang tinggi.
          Positioned.fill(
            child: Column(
              children: [
                const Expanded(
                  child: DecoratedBox(
                    decoration:
                        BoxDecoration(gradient: AppColors.splashGradient),
                    child: SizedBox.expand(),
                  ),
                ),
                Expanded(child: ColoredBox(color: scheme.surface)),
              ],
            ),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: DecoratedBox(
                decoration:
                    const BoxDecoration(gradient: AppColors.splashGradient),
                child: Column(
                  children: [
                    // Bagian atas: logo & nama aplikasi di atas latar gradasi.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/logo_mark_light.png',
                            width: 104,
                            height: 104,
                          ),
                          Text(
                            'Nilaya',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'LIVING',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: fontBody,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 8,
                              color: AppColors.lime,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hunian nyaman, warga terhubung',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    // Panel putih berisi form login.
                    Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(40)),
                        ),
                        padding: EdgeInsets.fromLTRB(24, 32, 24,
                            24 + MediaQuery.paddingOf(context).bottom),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const TwoToneHeading('Selamat datang,',
                                    'silakan masuk'),
                                const SizedBox(height: 8),
                                Text(
                                  store.isFirebase
                                      ? 'Gunakan akun yang diberikan pengelola.'
                                      : 'Pilih peran untuk mencoba aplikasi.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 24),
                                if (store.isFirebase)
                                  const _EmailLoginForm()
                                else
                                  ..._demoLogin(theme, scheme),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _demoLogin(ThemeData theme, ColorScheme scheme) {
    return [
      SegmentedButton<Role>(
        segments: const [
          ButtonSegment(
            value: Role.warga,
            label: Text('Warga'),
            icon: Icon(Icons.home_outlined),
          ),
          ButtonSegment(
            value: Role.pengelola,
            label: Text('Pengelola'),
            icon: Icon(Icons.admin_panel_settings_outlined),
          ),
        ],
        selected: {_role},
        onSelectionChanged: (s) => setState(() => _role = s.first),
      ),
      const SizedBox(height: 16),
      if (_role == Role.warga) ...[
        Text('Masuk sebagai warga:', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final r in store.residents.take(4))
                ListTile(
                  title: Text(r.name),
                  subtitle: Text('Rumah ${r.houseNo}'),
                  selected: r.id == _residentId,
                  trailing: r.id == _residentId
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () => setState(() => _residentId = r.id),
                ),
            ],
          ),
        ),
      ] else
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Pak Hendra'),
            subtitle: Text('Pengelola $estateName'),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => store.login(_role, residentId: _residentId),
        child: const Text('Masuk'),
      ),
      const SizedBox(height: 12),
      Text(
        'Mode demo: tanpa password, data hanya tersimpan di memori.',
        textAlign: TextAlign.center,
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ];
  }
}

class _EmailLoginForm extends StatefulWidget {
  const _EmailLoginForm();

  @override
  State<_EmailLoginForm> createState() => _EmailLoginFormState();
}

class _EmailLoginFormState extends State<_EmailLoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.signInWithEmail(_email.text.trim(), _password.text);
      // Berhasil: main.dart otomatis pindah ke HomeShell.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(
          () => _error = 'Isi email Anda dulu, lalu ketuk "Lupa password".');
      return;
    }
    await runAction(
      context,
      store.sendPasswordReset(email),
      success: 'Link reset password dikirim ke $email',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Email tidak valid' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Wajib diisi' : null,
              onFieldSubmitted: (_) => _signIn(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Masuk'),
            ),
            TextButton(
              onPressed: _busy ? null : _resetPassword,
              child: const Text('Lupa password'),
            ),
            const SizedBox(height: 8),
            Text(
              'Akun warga dibuatkan oleh pengelola perumahan.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
