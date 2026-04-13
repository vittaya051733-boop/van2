# van2

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deployment Notes

- Email OTP setup and SMTP/domain configuration: see `SMTP_DOMAIN_SETUP.md`
- Interactive SMTP secret setup: `scripts/set-firebase-smtp-secrets.ps1`
- Readiness check for SMTP secrets, function deploy, and DNS records: `scripts/check-email-otp-readiness.ps1`
- Web hosting deploy helper: `scripts/deploy-web-hosting.ps1`
