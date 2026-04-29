# van3

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase Deploy Shortcut

This project includes a shortcut script to deploy Firebase rules to the
`van-merchant` project without changing your existing commands in other projects.

Run in PowerShell:

```powershell
./scripts/deploy-van-merchant-rules.ps1
```

Optional deploy modes:

```powershell
./scripts/deploy-van-merchant-rules.ps1 -FirestoreOnly
./scripts/deploy-van-merchant-rules.ps1 -StorageOnly
```

You can also run the VS Code task:

- `Deploy Rules (van-merchant)`
