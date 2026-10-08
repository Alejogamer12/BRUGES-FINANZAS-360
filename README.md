# BRUGES FINANZAS 360

Aplicación Flutter para Android y Windows. La versión de compatibilidad actual es 1.2.0. Permite registrar ingresos y gastos localmente, consultar saldos por moneda, filtrar el historial y exportar CSV/JSON.

## Funciones disponibles

- Persistencia JSON local con migración, escritura atómica, deduplicación por ID y recuperación desde respaldo válido.
- Registro manual en COP, USD, EUR, MXN, GBP, CAD, BRL, PEN, CLP y ARS; los saldos nunca se suman entre monedas.
- Búsqueda y filtros por texto, tipo, moneda, entidad y fechas.
- Exportación CSV y JSON. Android abre el selector oficial de documentos; Windows guarda en `Documents\BRUGES-FINANZAS-360-Exportaciones`.
- Google Material Symbols sin conexión y una composición propia del símbolo de billetera con la B de BRUGES. No es un logo oficial de Google.
- Sugerencias opcionales a partir de notificaciones permitidas del sistema para entidades seleccionadas. Se guarda metadata normalizada y se evita persistir el título/cuerpo sin procesar. La estructura real de avisos bancarios no se ha comprobado con cuentas reales.
- Esquema y funciones Convex con autorización e idempotencia, cubiertos por pruebas unitarias; aún no hay un deployment configurado.

## Límites importantes

- Android mínimo API 24 (Android 7.0). El APK universal empaqueta `arm64-v8a`, `armeabi-v7a` y `x86_64`.
- No hay despliegue Convex, proveedor OIDC/correo ni inicio de sesión. La app permanece en modo «Solo local» y no sincroniza entre dispositivos.
- El JSON local no está cifrado a nivel de aplicación. La beta no debe usarse para almacenar información financiera sensible de otras personas.
- No están implementadas la administración real de cuentas, recuperación de contraseña, pagos/integraciones bancarias, biometría, mapas, push ni el actualizador automático.
- Android usa una clave de depuración: es apta para pruebas, no para Play Store ni distribución estable. El instalador de Windows no tiene firma Authenticode.
- La compatibilidad física con POCO/Xiaomi, Samsung u otras marcas está pendiente de pruebas en hardware. Consulta [el informe de verificación](INFORME-DE-VERIFICACION.txt).

## Descargas

Página pública que toma automáticamente los archivos de la versión estable más reciente (o de la beta más reciente mientras no haya estable): https://alejogamer12.github.io/BRUGES-FINANZAS-360/

## Desarrollo

Flutter/Dart: `flutter pub get`, `flutter analyze`, `flutter test`.

Backend: desde `backend/`, ejecutar `npm ci`, `npm test` y `npm run typecheck`.
