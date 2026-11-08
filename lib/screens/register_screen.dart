import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';
import 'password_screen.dart';

/// Registrasi mandiri warga: pilih rumah, isi data diri & akun, lalu
/// menunggu verifikasi pengelola.
///
/// [resubmit]: pendaftar yang ditolak memperbaiki data (akun sudah ada).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.resubmit = false});

  final bool resubmit;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  List<RegistrationEstate>? _estates;
  RegistrationEstate? _estate;
  RegistrationOptions? _options;
  bool _loadingOptions = false;
  String? _loadError;

  String? _clusterId;
  String? _typeId;
  String? _blockId;
  String? _houseId;

  Occupancy _occupancy = Occupancy.pemilik;

  /// Diisi bila rumah yang dipilih sudah berpenghuni (permintaan gabung).
  MemberRelation? _relation;
  bool _showRelationError = false;

  bool get _isJoin =>
      _houseId != null && (_options?.occupied.contains(_houseId) ?? false);
  XFile? _document;
  bool _obscure = true;
  bool _agree = false;
  bool _busy = false;
  bool _showHouseError = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    final prev = store.myRegistration;
    if (widget.resubmit && prev != null) {
      _name.text = prev.name;
      _phone.text = prev.phone;
      _occupancy = prev.occupancy;
      _relation = prev.relation;
    }
    _loadEstates();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadEstates() async {
    try {
      final list = await store.registrationEstates();
      if (!mounted) return;
      setState(() => _estates = list);
      final prevId = store.myRegistration?.estateId;
      final initial = list.where((e) => e.id == prevId).firstOrNull ??
          (list.length == 1 ? list.first : null);
      if (initial != null) await _selectEstate(initial);
    } catch (e) {
      if (mounted) setState(() => _loadError = describeError(e));
    }
  }

  Future<void> _selectEstate(RegistrationEstate e) async {
    setState(() {
      _estate = e;
      _options = null;
      _clusterId = _typeId = _blockId = _houseId = null;
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      final opts = await store.registrationOptions(e.id);
      if (!mounted) return;
      setState(() {
        _options = opts;
        final clusters = opts.clusters;
        if (clusters.length == 1) _clusterId = clusters.first.id;
        _autoFill();
      });
    } catch (err) {
      if (mounted) setState(() => _loadError = describeError(err));
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  /// Isi otomatis langkah yang pilihannya hanya satu.
  void _autoFill() {
    final o = _options;
    if (o == null || _clusterId == null) return;
    final types = o.typesOf(_clusterId!);
    if (_typeId == null && types.length == 1) _typeId = types.first.id;
    if (_typeId == null) return;
    final blocks = o.blocksOf(_clusterId!, _typeId!);
    if (_blockId == null && blocks.length == 1) _blockId = blocks.first.id;
  }

  Future<String?> _pick(String title, List<(String, String, String?, bool)> items,
      String? selected) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Tidak ada pilihan.'),
                ),
              for (final (id, label, sub, enabled) in items)
                ListTile(
                  title: Text(label),
                  subtitle: sub == null ? null : Text(sub),
                  enabled: enabled,
                  selected: id == selected,
                  onTap: () => Navigator.pop(ctx, id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _availability(RegistrationOptions o, Iterable<House> hs) {
    final list = hs.toList();
    return '${o.freeIn(list)} kosong · ${o.occupiedIn(list)} berpenghuni';
  }

  Future<void> _pickEstate() async {
    final list = _estates ?? const [];
    final id = await _pick(
      'Pilih perumahan',
      [for (final e in list) (e.id, e.name, e.address.isEmpty ? null : e.address, true)],
      _estate?.id,
    );
    if (id == null || id == _estate?.id) return;
    await _selectEstate(list.firstWhere((e) => e.id == id));
  }

  Future<void> _pickCluster() async {
    final o = _options!;
    final id = await _pick(
      'Pilih cluster',
      [
        for (final c in o.sortedClusters)
          (
            c.id,
            c.name,
            _availability(o, o.houses.where((h) => h.clusterId == c.id)),
            true,
          ),
      ],
      _clusterId,
    );
    if (id == null || id == _clusterId) return;
    setState(() {
      _clusterId = id;
      _typeId = _blockId = _houseId = null;
      _autoFill();
    });
  }

  Future<void> _pickType() async {
    final o = _options!;
    final id = await _pick(
      'Pilih tipe rumah',
      [
        for (final t in o.typesOf(_clusterId!))
          (
            t.id,
            t.name,
            [
              if (t.areaText.isNotEmpty) t.areaText,
              _availability(
                  o, o.blocksOf(_clusterId!, t.id).expand((b) => o.housesOf(b.id))),
            ].join(' · '),
            true,
          ),
      ],
      _typeId,
    );
    if (id == null || id == _typeId) return;
    setState(() {
      _typeId = id;
      _blockId = _houseId = null;
      _autoFill();
    });
  }

  Future<void> _pickBlock() async {
    final o = _options!;
    final id = await _pick(
      'Pilih blok',
      [
        for (final b in o.blocksOf(_clusterId!, _typeId!))
          (b.id, 'Blok ${b.name}', _availability(o, o.housesOf(b.id)), true),
      ],
      _blockId,
    );
    if (id == null || id == _blockId) return;
    setState(() {
      _blockId = id;
      _houseId = null;
    });
  }

  Future<void> _pickHouse() async {
    final o = _options!;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pilih no. rumah', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                  'Rumah kosong: daftar sebagai warga baru. Rumah bertanda '
                  'ikon orang sudah berpenghuni: ajukan gabung sebagai anggota '
                  'keluarga/penyewa. Nomor abu-abu sedang diajukan orang lain.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in o.housesOf(_blockId!))
                    ChoiceChip(
                      avatar: o.occupied.contains(h.id)
                          ? const Icon(Icons.person, size: 16)
                          : null,
                      label: Text(h.number),
                      selected: h.id == _houseId,
                      onSelected: o.selectable(h.id)
                          ? (_) => Navigator.pop(ctx, h.id)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (id != null) {
      setState(() {
        _houseId = id;
        _showHouseError = false;
      });
    }
  }

  Future<void> _submit() async {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _showHouseError = _houseId == null;
      _showRelationError = _isJoin && _relation == null;
    });
    if (!ok || _houseId == null || _showRelationError) return;
    if (!_agree) {
      showSnack(context, 'Centang pernyataan kebenaran data terlebih dahulu.');
      return;
    }
    final o = _options;
    final house = o?.houses.where((h) => h.id == _houseId).firstOrNull;
    final block = house == null
        ? null
        : o!.blocks.where((b) => b.id == house.blockId).firstOrNull;
    final confirmed = await confirmSave(context,
        title: _isJoin ? 'Ajukan gabung ke rumah ini?' : 'Kirim pendaftaran?',
        details: {
          'Perumahan': _estate?.name ?? '',
          'Rumah': house == null ? '' : '${block?.name ?? '?'}/${house.number}',
          'Nama': _name.text,
          'No. HP': _phone.text,
          'Status hunian': _occupancy.label,
          if (_isJoin && _relation != null) 'Hubungan': _relation!.label,
          if (!widget.resubmit) 'Email': _email.text,
          'Dokumen': _document == null ? 'Tidak dilampirkan' : 'Terlampir',
        },
        note: 'Data akan diverifikasi pengelola sebelum akun bisa dipakai.',
        action: 'Ya, kirim');
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.registerResident(
        estateId: _estate!.id,
        houseId: _houseId!,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        occupancy: _occupancy,
        email: widget.resubmit ? null : _email.text.trim(),
        password: widget.resubmit ? null : _password.text,
        document: _document,
        relation: _isJoin ? _relation : null,
      );
      if (!mounted) return;
      // Aplikasi otomatis menampilkan layar "menunggu verifikasi".
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

  /// Rumah berpenghuni: pendaftaran menjadi permintaan gabung.
  Widget _joinCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Rumah ini sudah berpenghuni',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSecondaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Anda akan mengajukan diri sebagai anggota rumah. Permintaan '
              'disetujui oleh kepala keluarga rumah ini atau pengelola.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            Text('Hubungan Anda dengan kepala keluarga',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSecondaryContainer)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in MemberRelation.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _relation == r,
                    onSelected: (_) => setState(() {
                      _relation = r;
                      _showRelationError = false;
                    }),
                  ),
              ],
            ),
            if (_showRelationError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Pilih hubungan',
                    style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = _options;
    final cluster = o?.clusters.where((c) => c.id == _clusterId).firstOrNull;
    final type = o?.types.where((t) => t.id == _typeId).firstOrNull;
    final block = o?.blocks.where((b) => b.id == _blockId).firstOrNull;
    final house = o?.houses.where((h) => h.id == _houseId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.resubmit ? 'Perbaiki Pendaftaran' : 'Daftar Warga')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Isi data dengan benar. Pengelola akan memverifikasi sebelum '
              'akun Anda aktif.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            const _Section(number: 1, title: 'Rumah Anda'),
            if (_estates == null && _loadError == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_estates != null && _estates!.isEmpty)
              const Text('Belum ada perumahan yang membuka pendaftaran online. '
                  'Hubungi pengelola perumahan Anda.')
            else ...[
              _Box(
                label: 'Perumahan',
                value: _estate?.name,
                icon: Icons.location_city_outlined,
                onTap: _busy ? null : _pickEstate,
              ),
              if (_loadingOptions)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              if (o != null && o.houses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Perumahan ini belum memiliki data rumah.'),
                ),
              if (o != null && o.houses.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Box(
                  label: 'Cluster',
                  value: cluster?.name,
                  icon: Icons.holiday_village_outlined,
                  onTap: _busy ? null : _pickCluster,
                ),
                const SizedBox(height: 10),
                _Box(
                  label: 'Tipe rumah',
                  value: type == null
                      ? null
                      : [type.name, if (type.areaText.isNotEmpty) type.areaText]
                          .join(' · '),
                  icon: Icons.straighten,
                  onTap: _busy || cluster == null ? null : _pickType,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Box(
                        label: 'Blok',
                        value: block?.name,
                        icon: Icons.grid_view,
                        onTap: _busy || type == null ? null : _pickBlock,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Box(
                        label: 'No. rumah',
                        value: house?.number,
                        icon: Icons.home_outlined,
                        onTap: _busy || block == null ? null : _pickHouse,
                        errorText: _showHouseError ? 'Pilih rumah' : null,
                      ),
                    ),
                  ],
                ),
                if (_isJoin) _joinCard(theme),
              ],
            ],
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_loadError!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 24),
            const _Section(number: 2, title: 'Data diri'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Nama lengkap (sesuai KTP)',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: 'No. HP / WhatsApp',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 9 ? 'No. HP tidak valid' : null;
              },
            ),
            if (!_isJoin) ...[
              const SizedBox(height: 12),
              Text('Status hunian', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final oc in Occupancy.values)
                    ChoiceChip(
                      label: Text(oc.label),
                      selected: _occupancy == oc,
                      onSelected: (_) => setState(() => _occupancy = oc),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('Foto KTP / bukti hunian (opsional)',
                style: theme.textTheme.labelLarge),
            Text('Mempercepat verifikasi: KTP, AJB/sertifikat, atau kontrak sewa.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_document != null)
                  RemovablePhoto(
                    source: _document!.path,
                    onRemove: () => setState(() => _document = null),
                  )
                else
                  AddPhotoButton(
                    label: 'Foto\ndokumen',
                    onPressed: _busy
                        ? null
                        : () async {
                            final f = await pickPhoto(context);
                            if (f != null && mounted) {
                              setState(() => _document = f);
                            }
                          },
                  ),
              ],
            ),
            if (!widget.resubmit) ...[
              const SizedBox(height: 24),
              const _Section(number: 3, title: 'Akun login'),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) => (v == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                    ? 'Email tidak valid'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Minimal 8 karakter, berisi huruf dan angka',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => passwordProblem(v ?? ''),
              ),
              const SizedBox(height: 8),
              PasswordStrength(_password.text),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Ulangi password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    v != _password.text ? 'Password tidak sama' : null,
              ),
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              title: const Text('Saya menyatakan data di atas benar dan saya '
                  'penghuni/pemilik rumah tersebut.'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _estate == null ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_busy
                  ? 'Mengirim...'
                  : widget.resubmit
                      ? 'Ajukan ulang'
                      : _isJoin
                          ? 'Ajukan gabung'
                          : 'Daftar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.lime,
            foregroundColor: Colors.white,
            child: Text('$number',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(radiusField),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: onTap != null,
          errorText: errorText,
        ),
        child: Text(value ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Layar pendaftar setelah mengirim pendaftaran: menunggu verifikasi, atau
/// ditolak (dengan alasan) dan bisa mengajukan ulang.
class PendingRegistrationScreen extends StatelessWidget {
  const PendingRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reg = store.myRegistration;
    final rejected = reg?.status == RegistrationStatus.ditolak;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(
              rejected ? Icons.error_outline : Icons.hourglass_top_rounded,
              size: 72,
              color: rejected ? scheme.error : AppColors.lime,
            ),
            const SizedBox(height: 16),
            TwoToneHeading(
              'Halo, ${store.currentUser?.name ?? ''}',
              rejected ? 'pendaftaran ditolak' : 'menunggu verifikasi',
            ),
            const SizedBox(height: 8),
            Text(
              rejected
                  ? 'Pendaftaran Anda belum dapat disetujui. Perbaiki data '
                      'sesuai catatan di bawah lalu ajukan ulang.'
                  : reg?.isJoin == true
                      ? 'Permintaan gabung Anda sedang menunggu persetujuan '
                          'kepala keluarga rumah ini atau pengelola. Aplikasi '
                          'akan terbuka otomatis setelah disetujui.'
                      : 'Pendaftaran Anda sudah diterima dan sedang diperiksa '
                          'pengelola. Aplikasi akan terbuka otomatis setelah '
                          'disetujui.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (reg != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rumah ${reg.houseNo}',
                          style: theme.textTheme.titleMedium),
                      if (reg.clusterName.isNotEmpty) Text(reg.clusterName),
                      const SizedBox(height: 8),
                      Text(reg.isJoin
                          ? '${reg.name} · gabung sebagai '
                              '${reg.relation?.label ?? 'anggota'}'
                          : '${reg.name} · ${reg.occupancy.label}'),
                      Text('${reg.phone} · ${reg.email}',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text('Dikirim ${formatDate(reg.createdAt)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            if (rejected && reg!.note.isNotEmpty)
              Card(
                color: scheme.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.sticky_note_2_outlined,
                      color: scheme.onErrorContainer),
                  title: Text('Catatan pengelola',
                      style: TextStyle(color: scheme.onErrorContainer)),
                  subtitle: Text(reg.note,
                      style: TextStyle(color: scheme.onErrorContainer)),
                ),
              ),
            const SizedBox(height: 24),
            if (rejected)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RegisterScreen(resubmit: true))),
                icon: const Icon(Icons.edit),
                label: const Text('Perbaiki & ajukan ulang'),
              ),
            TextButton(
              onPressed: () => store.logout(),
              child: const Text('Keluar'),
            ),
          ],
        ),
      ),
    );
  }
}
