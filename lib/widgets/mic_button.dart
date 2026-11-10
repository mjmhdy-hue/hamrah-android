import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/native_bridge.dart';
import '../providers.dart';

class MicButton extends ConsumerStatefulWidget {
  const MicButton({super.key, required this.onTranscript, this.enabled = true, this.tooltip = 'ورودی صوتی'});

  final ValueChanged<String> onTranscript;
  final bool enabled;
  final String tooltip;

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<MicButton> {
  bool _listening = false;

  Future<void> _start() async {
    final settings = ref.read(settingsRepoProvider);
    if (!await settings.voiceEnabled()) {
      _showMessage('ورودی صوتی در تنظیمات خاموش است.');
      return;
    }
    final consentShown = await settings.voiceConsentShown();
    if (!consentShown) {
      final accepted = await _askConsent();
      if (!accepted) return;
      await settings.put('voice_consent_shown', '1');
    }
    final bridge = ref.read(bridgeProvider);
    final permission = await bridge.micPermissionState();
    if (permission != 'granted') {
      await bridge.requestMicPermission();
      _showMessage('برای استفاده از میکروفن، اجازهٔ ضبط صدا را در پنجرهٔ سیستم تأیید کنید.');
      return;
    }
    final voice = ref.read(voiceServiceProvider);
    if (!await voice.ensureInitialized()) {
      _showMessage('سرویس تشخیص گفتار این دستگاه در دسترس نیست؛ متن را تایپ کنید. جزئیات در عیب‌یابی.');
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
    final text = await voice.listenOnce(localeId: 'fa_IR');
    if (!mounted) return;
    setState(() => _listening = false);
    if (text != null && text.trim().isNotEmpty) {
      widget.onTranscript(text.trim());
    } else if (text == null) {
      _showMessage('متن گفتار دریافت نشد. دوباره تلاش کنید یا متن را تایپ کنید.');
    }
  }

  Future<bool> _askConsent() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ورودی صوتی'),
        content: const Text(
          'تشخیص گفتار را سرویس گفتار دستگاه انجام می‌دهد و بسته به دستگاه ممکن است آنلاین باشد. '
          'فقط واژه‌هایی که می‌گویید فرستاده می‌شود؛ هرگز متن پیامک یا مبلغ تراکنش‌ها ارسال نمی‌شود. '
          'میکروفن فقط وقتی این دکمه را می‌زنید فعال می‌شود.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('فعلاً نه')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('متوجه شدم')),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: widget.tooltip,
      onPressed: !widget.enabled || _listening ? null : _start,
      icon: Icon(_listening ? Icons.graphic_eq : Icons.mic_none_outlined),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
