import 'package:flutter/material.dart';

import '../services/language_service.dart';

class AppLocalizations {
  AppLocalizations._();

  static const Map<String, String> _ruToEn = {
    'Password Manager': 'Password Manager',
    'Настройки': 'Settings',
    'Введите логин': 'Enter login',
    'Введите пароль': 'Enter password',
    'Введите новый пароль': 'Enter new password',
    'Введите TOTP код': 'Enter TOTP code',
    'Введите код': 'Enter code',
    'Только цифры': 'Digits only',
    '6 цифр': '6 digits',
    'Минимум 3 символа': 'At least 3 characters',
    'Минимум 14 символов': 'At least 14 characters',
    'Сгенерировать надежный пароль': 'Generate a strong password',
    'URL сервера': 'Server URL',
    'Темная': 'Dark',
    'Добро пожаловать!': 'Welcome!',
    'Забыли пароль?': 'Forgot password?',
    'Зарегистрироваться': 'Sign up',
    'Нет аккаунта? Зарегистрироваться': 'No account? Sign up',
    'Уже есть аккаунт? Войти': 'Already have an account? Sign in',
    'Создание защищенного аккаунта': 'Creating a secure account',
    'Защищенный вход в хранилище': 'Secure vault access',
    'Для доступа к приложению': 'To access the app',
    'Введите PIN-код': 'Enter PIN code',
    'Использовать биометрию': 'Use biometrics',
    'Используйте PIN-код для быстрого доступа': 'Use a PIN for quick access',
    'PIN обязателен: мастер-ключ больше не сохраняется без локального секрета.': 'PIN is required: the master key is no longer stored without a local secret.',
    'PIN-код должен содержать 6 цифр': 'PIN code must contain 6 digits',
    'Диагностическая информация': 'Diagnostic information',
    'Доступные методы:': 'Available methods:',
    'Технические названия:': 'Technical names:',
    'Результат теста': 'Test result',
    'Тестирование': 'Testing',
    'Период ожидания': 'Wait period',
    'Привязка Telegram': 'Telegram binding',
    'Введите ваш Telegram Chat ID для получения уведомлений о безопасности.': 'Enter your Telegram Chat ID to receive security notifications.',
    'Мы будем присылать оповещения о входе, изменении паролей и попытках взлома в ваш Telegram.': 'We will send sign-in, password-change, and attack alerts to your Telegram.',
    'Узнать свой ID можно через бота @userinfobot или аналогичные.': 'You can get your ID via @userinfobot or a similar bot.',
    'Получайте уведомления о безопасности!': 'Receive security notifications!',
    'Выберите тему': 'Choose theme',
    'Настройка сервера': 'Server setup',
    'Пожалуйста, укажите URL вашего сервера Zero Vault. ': 'Please enter your Zero Vault server URL. ',
    'Вы будете перенаправлены на экран входа.': 'You will be redirected to the sign-in screen.',
    'Безопасное хранение и управление паролями.': 'Secure password storage and management.',
    'С любовью к безопасности и удобству': 'Made with love for security and convenience',
    'Сбросить пароль': 'Reset password',
    'Создайте папку сначала': 'Create a folder first',
    'Создать новую папку': 'Create a new folder',
    'Выбрать папку': 'Choose folder',
    'Выбрать папку (необязательно)': 'Choose folder (optional)',
    'Без папки': 'No folder',
    'Отозвать': 'Revoke',
    'Отозван': 'Revoked',
    'Повторить': 'Retry',
    'Подтверждение': 'Confirmation',
    'Выйти из аккаунта?': 'Log out of the account?',
    'Введите TOTP-код для отображения скрытых папок': 'Enter the TOTP code to reveal hidden folders',
    'Защита 2FA': '2FA protection',
    'Отсканируйте код в приложении (Google Authenticator / Aegis):': 'Scan the code in your authenticator app (Google Authenticator / Aegis):',
    'Ошибка инициализации 2FA': '2FA initialization error',
    'Важное предупреждение!': 'Important warning!',
    'Передайте ключ получателю отдельным каналом. Ключ отображается только один раз.': 'Send the key to the recipient through a separate channel. The key is shown only once.',
    'Введите ключ, полученный от отправителя:': 'Enter the key received from the sender:',
    'Пароль шифруется одноразовым ключом': 'The password is encrypted with a one-time key',
    'Создать ссылку': 'Create link',
    'Биометрия включена': 'Biometrics enabled',
    'Биометрическая аутентификация не удалась. Используйте PIN-код.': 'Biometric authentication failed. Use your PIN code.',
    'Биометрическая аутентификация принудительно включена': 'Biometric authentication has been force-enabled',
    'Введите 6-значный код безопасности для подтверждения действия.': 'Enter the 6-digit security code to confirm the action.',
    'Ошибка при сохранении темы': 'Error while saving theme',
    'Ошибка при получении диагностики': 'Error while fetching diagnostics',
    'Ошибка при включении биометрии': 'Error while enabling biometrics',
    'Ошибка при сбросе настроек': 'Error while resetting settings',
    'Ошибка импорта': 'Import error',
    'Отключите скрытие в настройках, чтобы увидеть записи': 'Disable hiding in settings to view entries',
    'Сброс пароля позволит войти в аккаунт, но НЕ восстановит доступ к зашифрованным паролям в сейфе автоматически. ': 'Password reset will restore account access, but it will NOT automatically restore access to encrypted passwords in the vault. ',
    'Безопасность': 'Security',
    'PIN-код': 'PIN code',
    'PIN-код установлен': 'PIN code is set',
    'PIN-код не установлен': 'PIN code is not set',
    'Изменить': 'Change',
    'Удалить': 'Delete',
    'Установить': 'Set',
    'Скрыть записи с seed фразами': 'Hide entries with seed phrases',
    'Записи с seed фразами скрыты из списка': 'Entries with seed phrases are hidden from the list',
    'Записи с seed фразами отображаются в списке': 'Entries with seed phrases are shown in the list',
    'Биометрическая аутентификация': 'Biometric authentication',
    'Биометрическая аутентификация включена': 'Biometric authentication is enabled',
    'Биометрическая аутентификация отключена': 'Biometric authentication is disabled',
    'Диагностика биометрии': 'Biometric diagnostics',
    'Проверить состояние биометрической аутентификации': 'Check biometric authentication status',
    'Тест биометрии': 'Biometric test',
    'Подробное тестирование биометрической аутентификации': 'Detailed biometric authentication testing',
    'Фраза восстановления': 'Recovery phrase',
    'Просмотр фразы восстановления аккаунта': 'View the account recovery phrase',
    'Фраза восстановления не установлена': 'Recovery phrase is not set',
    'История паролей': 'Password history',
    'Просмотр истории изменений паролей': 'View password change history',
    'Скрытые папки': 'Hidden folders',
    'Показывать скрытые папки': 'Show hidden folders',
    'Разблокировано на эту сессию': 'Unlocked for this session',
    'Требуется TOTP для включения': 'TOTP is required to enable',
    'Организация': 'Organization',
    'Папки': 'Folders',
    'Управление папками и категориями': 'Manage folders and categories',
    'Интерфейс': 'Interface',
    'Тема приложения': 'App theme',
    'Язык': 'Language',
    'Выберите язык интерфейса': 'Choose the interface language',
    'Русский': 'Russian',
    'English': 'English',
    'Сервер': 'Server',
    'Текущий сервер': 'Current server',
    'Не задан': 'Not set',
    'Аккаунт': 'Account',
    'Профиль': 'Profile',
    'Загрузка...': 'Loading...',
    'Уведомления Telegram': 'Telegram notifications',
    'Уведомления не настроены': 'Notifications are not configured',
    'Passkeys (Безопасный вход)': 'Passkeys (Secure sign-in)',
    'Passkeys': 'Passkeys',
    'Управление ключами доступа для беспарольного входа': 'Manage passkeys for passwordless sign-in',
    'Выйти': 'Log out',
    'Отмена': 'Cancel',
    'Подтвердить': 'Confirm',
    'Продолжить': 'Continue',
    'Закрыть': 'Close',
    'Сохранить': 'Save',
    'Копировать': 'Copy',
    'Готово': 'Done',
    'Принять': 'Accept',
    'Отключить': 'Disable',
    'Поделиться': 'Share',
    'Расшифровать': 'Decrypt',
    'Проверить': 'Check',
    'Привязать Telegram': 'Bind Telegram',
    'Регистрация успешно завершена': 'Registration completed successfully',
    'Сгенерирован надежный пароль': 'A strong password has been generated',
    'Не удалось сгенерировать пароль': 'Failed to generate a password',
    'Ошибка подключения к серверу': 'Server connection error',
    'Ошибка подключения': 'Connection error',
    'Ошибка подтверждения': 'Confirmation error',
    'Ошибка подтверждения смены сервера': 'Server change confirmation error',
    'Подтверждение смены сервера': 'Confirm server change',
    'Ошибка': 'Error',
    'Ошибка OTP': 'OTP error',
    'Ошибка дешифрования': 'Decryption error',
    'Ошибка расшифровки': 'Decryption error',
    'Ошибка аутентификации': 'Authentication error',
    'Ошибка проверки PIN-кода': 'PIN verification error',
    'Ошибка при выполнении операции': 'Operation error',
    'Ошибка сохранения PIN-кода': 'PIN save error',
    'Ошибка загрузки профиля': 'Profile loading error',
    'Telegram успешно привязан': 'Telegram linked successfully',
    'Ошибка привязки': 'Binding error',
    'Ошибка загрузки фразы': 'Failed to load phrase',
    'Фраза восстановления не настроена': 'Recovery phrase is not configured',
    'Не удалось подтвердить доступ': 'Failed to confirm access',
    'Неверный TOTP код': 'Invalid TOTP code',
    'Неверный TOTP-код': 'Invalid TOTP code',
    'Тема изменена на': 'Theme changed to',
    'Настройки Telegram сохранены': 'Telegram settings saved',
    'Passkey успешно зарегистрирован': 'Passkey registered successfully',
    'Ошибка регистрации Passkey': 'Passkey registration error',
    'Фраза скопирована в буфер обмена': 'Phrase copied to clipboard',
    'Фраза восстановления успешно создана': 'Recovery phrase created successfully',
    'Создать фразу восстановления?': 'Create a recovery phrase?',
    'Это позволит восстановить доступ к аккаунту при потере пароля. Фраза будет сгенерирована на устройстве.': 'This lets you restore access to your account if you lose your password. The phrase will be generated on the device.',
    'Никому не сообщайте эту фразу! Она дает полный доступ к вашему аккаунту и данным.': 'Do not share this phrase with anyone. It grants full access to your account and data.',
    'Для просмотра фразы восстановления введите TOTP код из приложения.': 'To view the recovery phrase, enter the TOTP code from your authenticator app.',
    'TOTP Код': 'TOTP code',
    'Защита 2FA': '2FA protection',
    'Защита аккаунта': 'Account protection',
    'ПОДТВЕРДИТЬ': 'CONFIRM',
    'Войти с Passkey': 'Sign in with Passkey',
    'Ошибка входа через Passkey': 'Passkey sign-in error',
    'Сброс пароля': 'Reset password',
    'Пароль успешно сброшен. Теперь вы можете войти.': 'Password reset successfully. You can now sign in.',
    'Настройка сервера': 'Server setup',
    'Устройство небезопасно': 'Device is not secure',
    'Обнаружены root-права или модификация системы. В целях защиты ваших паролей приложение заблокировано.': 'Root access or system modification has been detected. The app is blocked to protect your passwords.',
    'Закрыть приложение': 'Close app',
    'Пароль': 'Password',
    'Заметки': 'Notes',
    'Seed-фраза': 'Seed phrase',
    'Редактировать': 'Edit',
    'Редактировать пароль': 'Edit password',
    'Логин не указан': 'Login not provided',
    'Скопировать логин': 'Copy login',
    'Скрыть': 'Hide',
    'Показать': 'Show',
    'Скопировать пароль': 'Copy password',
    'Копировать (авто-очистка через 30с)': 'Copy (auto-clear after 30s)',
    'Скопировано (авто-очистка через 30с)': 'Copied (auto-clear after 30s)',
    'Без срока': 'No expiration',
    '1 день': '1 day',
    '7 дней': '7 days',
    '30 дней': '30 days',
    'Введите логин получателя': 'Enter recipient login',
    'Выберите пароль для отправки': 'Select a password to send',
    'Скрытая папка': 'Hidden folder',
    'Требует TOTP для просмотра': 'Requires TOTP to view',
    'Переместить в папку': 'Move to folder',
    'Поделиться паролем': 'Share password',
    'Удалить папку': 'Delete folder',
    'Создать папку': 'Create folder',
    'Цвет': 'Color',
    'Иконка': 'Icon',
    'Всего паролей': 'Total passwords',
    'Логин': 'Login',
    'Привязан Chat ID': 'Bound Chat ID',
    'Успешно импортировано': 'Successfully imported',
    'паролей': 'passwords',
    'Ошибка импорта': 'Import error',
    'Обновлено фавиконок': 'Favicons updated',
    'Ошибка при обновлении фавиконок': 'Error while updating favicons',
    'Ошибка соединения': 'Connection error',
    'Ошибка при создании фразы': 'Error while creating the phrase',
    'Ошибка при сохранении настроек': 'Error while saving settings',
    'Ошибка при выходе': 'Error while logging out',
    'Хранилище заблокировано. Войдите через PIN для включения биометрии.': 'Vault is locked. Sign in with your PIN to enable biometrics.',
    'Не удалось сохранить ключ. Попробуйте снова.': 'Failed to save the key. Please try again.',
    'Ошибка при включении биометрической аутентификации': 'Error while enabling biometric authentication',
    'Ошибка при отключении биометрической аутентификации': 'Error while disabling biometric authentication',
    'Настройки биометрии сброшены': 'Biometric settings reset',
    'Ошибка при сбросе настроек': 'Error while resetting settings',
    'Ошибка при включении биометрии': 'Error while enabling biometrics',
    'PIN-код удален': 'PIN code removed',
    'Ошибка при удалении PIN-кода': 'Error while removing PIN code',
    'Пароль': 'Password',
    'Войти': 'Sign in',
    'Регистрация': 'Sign up',
    'Сохранить сервер': 'Save server',
    'Проверить соединение': 'Check connection',
    'Неверный логин или пароль': 'Invalid login or password',
    'Ошибка валидации полей': 'Field validation error',
    'Ошибка разбора ответа сервера': 'Failed to parse server response',
    'Unknown error': 'Unknown error',
    'Неизвестная ошибка': 'Unknown error',
    'Invalid credentials': 'Invalid credentials',
    'Invalid authentication': 'Invalid authentication',
    'OTP_REQUIRED': 'OTP required',
    'Password too weak. Minimum 14 characters, including uppercase, lowercase, digits, and special symbols.': 'Password too weak. Minimum 14 characters, including uppercase, lowercase, digits, and special symbols.',
    'Resource not found or access denied': 'Resource not found or access denied',
    'Seed phrase not set': 'Seed phrase not set',
    'Seed phrase required': 'Seed phrase required',
    'Valid TOTP verification required': 'Valid TOTP verification required',
    'Invalid MFA token': 'Invalid MFA token',
    'MFA token already used': 'MFA token already used',
    'Invalid token': 'Invalid token',
    'Invalid refresh token': 'Invalid refresh token',
    'Account temporarily locked. Try again later.': 'Account temporarily locked. Try again later.',
    '2FA is already enabled': '2FA is already enabled',
    'Copied': 'Copied',
    'Confirm': 'Confirm',
    'Done': 'Done',
    'Close': 'Close',
    'Cancel': 'Cancel',
    'Invite': 'Invite',
    'Invitation sent to': 'Invitation sent to',
    'Vault Uploaded': 'Vault uploaded',
    'Access Emergency Vault': 'Access emergency vault',
    'Emergency Vault': 'Emergency vault',
    'Emergency Access': 'Emergency access',
    'Add Contact': 'Add contact',
    'No emergency contacts yet': 'No emergency contacts yet',
    'Upload Vault': 'Upload vault',
    'Check In': 'Check in',
    'Deny': 'Deny',
    'Revoke': 'Revoke',
    'No emergency access granted to you': 'No emergency access granted to you',
    'Accept Invite': 'Accept invite',
    'Access requested. Timer started.': 'Access requested. Timer started.',
    'Request Access': 'Request access',
    'Get Vault': 'Get vault',
    'Wait period': 'Wait period',
    'days': 'days',
    'Add Emergency Contact': 'Add Emergency Contact',
  };

  static final Map<String, String> _enToRu = {
    for (final entry in _ruToEn.entries) entry.value: entry.key,
  };

  static String translate(String text, Locale locale) {
    final languageCode = locale.languageCode;
    if (text.isEmpty) return text;

    final direct = languageCode == 'en' ? _ruToEn[text] : _enToRu[text];
    if (direct != null) return direct;

    final dynamicTranslated = _translateDynamic(text, languageCode);
    return dynamicTranslated ?? text;
  }

  static String translateStandalone(String text, {String? languageCode}) {
    return translate(text, Locale(languageCode ?? LanguageService.instance.languageCode));
  }

  static String? _translateDynamic(String text, String languageCode) {
    String translateInner(String value) => translateStandalone(value, languageCode: languageCode);

    final errorPrefix = RegExp(r'^(Ошибка|Error):\s+(.+)$');
    final errorMatch = errorPrefix.firstMatch(text);
    if (errorMatch != null) {
      final prefix = languageCode == 'en' ? 'Error' : 'Ошибка';
      return '$prefix: ${translateInner(errorMatch.group(2)!)}';
    }

    final connectionPrefix = RegExp(r'^(Ошибка соединения|Connection error):\s+(.+)$');
    final connectionMatch = connectionPrefix.firstMatch(text);
    if (connectionMatch != null) {
      final prefix = languageCode == 'en' ? 'Connection error' : 'Ошибка соединения';
      return '$prefix: ${translateInner(connectionMatch.group(2)!)}';
    }

    final importPrefix = RegExp(r'^(Ошибка импорта|Import error):\s+(.+)$');
    final importPrefixMatch = importPrefix.firstMatch(text);
    if (importPrefixMatch != null) {
      final prefix = languageCode == 'en' ? 'Import error' : 'Ошибка импорта';
      return '$prefix: ${translateInner(importPrefixMatch.group(2)!)}';
    }

    final diagnosticsPrefix = RegExp(r'^(Ошибка при получении диагностики|Error while fetching diagnostics):\s+(.+)$');
    final diagnosticsMatch = diagnosticsPrefix.firstMatch(text);
    if (diagnosticsMatch != null) {
      final prefix = languageCode == 'en'
          ? 'Error while fetching diagnostics'
          : 'Ошибка при получении диагностики';
      return '$prefix: ${translateInner(diagnosticsMatch.group(2)!)}';
    }

    final loginSummary = RegExp(r'^(Логин|Login):\s*(.+)\n(Всего паролей|Total passwords):\s*(\d+)$');
    final loginMatch = loginSummary.firstMatch(text);
    if (loginMatch != null) {
      if (languageCode == 'en') {
        return 'Login: ${loginMatch.group(2)}\nTotal passwords: ${loginMatch.group(4)}';
      }
      return 'Логин: ${loginMatch.group(2)}\nВсего паролей: ${loginMatch.group(4)}';
    }

    final chatId = RegExp(r'^(Привязан Chat ID|Bound Chat ID):\s*(.+)$');
    final chatMatch = chatId.firstMatch(text);
    if (chatMatch != null) {
      return languageCode == 'en'
          ? 'Bound Chat ID: ${chatMatch.group(2)}'
          : 'Привязан Chat ID: ${chatMatch.group(2)}';
    }

    final importPasswords = RegExp(r'^(Успешно импортировано|Successfully imported)\s+(\d+)\s+(паролей|passwords)$');
    final importMatch = importPasswords.firstMatch(text);
    if (importMatch != null) {
      return languageCode == 'en'
          ? 'Successfully imported ${importMatch.group(2)} passwords'
          : 'Успешно импортировано ${importMatch.group(2)} паролей';
    }

    final faviconUpdated = RegExp(r'^(Обновлено фавиконок|Favicons updated):\s*(\d+)$');
    final faviconMatch = faviconUpdated.firstMatch(text);
    if (faviconMatch != null) {
      return languageCode == 'en'
          ? 'Favicons updated: ${faviconMatch.group(2)}'
          : 'Обновлено фавиконок: ${faviconMatch.group(2)}';
    }

    final themeChanged = RegExp(r'^(Тема изменена на|Theme changed to)\s+(.+)$');
    final themeMatch = themeChanged.firstMatch(text);
    if (themeMatch != null) {
      final prefix = languageCode == 'en' ? 'Theme changed to' : 'Тема изменена на';
      return '$prefix ${translateInner(themeMatch.group(2)!)}';
    }

    final invitationSent = RegExp(r'^(Invitation sent to)\s+(.+)$');
    final invitationSentRu = RegExp(r'^(Приглашение отправлено пользователю)\s+(.+)$');
    if (invitationSent.hasMatch(text)) {
      final target = invitationSent.firstMatch(text)!.group(2)!;
      return languageCode == 'en' ? text : 'Приглашение отправлено пользователю $target';
    }
    if (invitationSentRu.hasMatch(text)) {
      final target = invitationSentRu.firstMatch(text)!.group(2)!;
      return languageCode == 'en' ? 'Invitation sent to $target' : text;
    }

    final waitPeriod = RegExp(r'^(Wait period|Период ожидания):\s*(\d+)\s*(days|дней)$');
    final waitMatch = waitPeriod.firstMatch(text);
    if (waitMatch != null) {
      return languageCode == 'en'
          ? 'Wait period: ${waitMatch.group(2)} days'
          : 'Период ожидания: ${waitMatch.group(2)} дней';
    }

    final emergencyVault = RegExp(r'^(Emergency Vault|Экстренное хранилище)\s*\((\d+)\s*(entries|записей)\)$');
    final vaultMatch = emergencyVault.firstMatch(text);
    if (vaultMatch != null) {
      return languageCode == 'en'
          ? 'Emergency Vault (${vaultMatch.group(2)} entries)'
          : 'Экстренное хранилище (${vaultMatch.group(2)} записей)';
    }

    final biometricDisabled = RegExp(r'^(.*) отключен$');
    final biometricDisabledMatch = biometricDisabled.firstMatch(text);
    if (biometricDisabledMatch != null && text.contains('отключен')) {
      return languageCode == 'en'
          ? '${translateInner(biometricDisabledMatch.group(1)!)} disabled'
          : text;
    }

    return null;
  }
}

extension AppLocalizationsX on BuildContext {
  String tr(String text) => AppLocalizations.translate(text, Localizations.localeOf(this));
}
