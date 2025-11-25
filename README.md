# cuartel_bombermans

Proyecto Flutter: `cuartel_bombermans`

Este archivo muestra la estructura principal del proyecto para que sea
fácil entender la organización de carpetas y archivos.

**Estructura del proyecto**

```
.

├── android/
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── models/
│   │   └── form_template.dart
│   ├── screens/
│   │   ├── admin_projects_screen.dart
│   │   ├── admin_retos_list_screen.dart
│   │   ├── admin_reto_form_screen.dart
│   │   ├── evidencias_screen.dart
│   │   ├── evidencia_detalle_screen.dart
│   │   ├── formularios_enviados_screen.dart
│   │   ├── formulario_detalle_screen.dart
│   │   ├── formulario_lleno_screen.dart
│   │   ├── form_templates_list_screen.dart
│   │   ├── home_shell.dart
│   │   ├── leaderboard_screen.dart
│   │   ├── login_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── register_screen.dart
│   │   ├── retos_screen.dart
│   │   └── verify_email_screen.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── imgbb_service.dart
│   │   ├── roles.dart
│   │   ├── session.dart
│   │   └── user_lookup.dart
│   └── widgets/
│       ├── loading_indicator.dart
│       ├── reviewer_name.dart
│       └── signature_field.dart
│       ├── formulario_detalle_screen.dart
│       ├── formulario_lleno_screen.dart
│       ├── form_templates_list_screen.dart
│       ├── home_shell.dart
│       ├── leaderboard_screen.dart
│       ├── login_screen.dart
│       ├── profile_screen.dart
│       ├── register_screen.dart
│       ├── retos_screen.dart
│       └── verify_email_screen.dart
│   
│   
├── test/
│   ├── services/
│   └── widgets/
├── web/
│   ├── index.html
│   ├── manifest.json
│   └── icons/
├── windows/
│   └── runner/
├── macos/
│   └── Runner/
├── linux/
├── integration_test/
│   └── app_e2e_test.dart
├── images/
├── lottie/
├── android/ (otros archivos de Gradle)
├── build/
│   ├── 313d2bb2bab7b1d1ebcf96bb0bf926a2/
│   │   ├── _composite.stamp
│   │   ├── gen_dart_plugin_registrant.stamp
│   │   └── gen_localizations.stamp
│   ├── 58e779e20a1068f9d7045294e6a915ac/
│   │   ├── _composite.stamp
│   │   ├── gen_dart_plugin_registrant.stamp
│   │   └── gen_localizations.stamp
│   ├── app/
│   │   ├── generated/
│   │   ├── intermediates/
│   │   ├── kotlin/
│   │   └── outputs/
│   └── flutter_assets/
├── flutter/
│   ├── analysis_options.yaml
│   ├── bin/
│   ├── packages/
│   └── examples/
├── firebase.json
├── pubspec.yaml
├── analysis_options.yaml
├── cuartel_bombermans.iml
├── android/ (configuración de proyecto Android)
├── build.gradle.kts
├── gradle/
│   └── wrapper/
├── gradlew
├── gradlew.bat
├── key.properties
├── local.properties
├── app/
│   ├── build.gradle.kts
+│   └── src/
└── README.md

```

**Notas rápidas**
- `lib/`: código Dart de la app (punto de entrada en `main.dart`).
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`: carpetas específicas
	de cada plataforma con sus ajustes y código nativo.
- `test/` e `integration_test/`: pruebas unitarias y pruebas de integración.
- `pubspec.yaml`: dependencias y recursos del proyecto.

Si quieres, puedo adaptar o expandir este árbol para mostrar más niveles
(por ejemplo, contenido detallado dentro de `lib/` o `android/app/src`).
