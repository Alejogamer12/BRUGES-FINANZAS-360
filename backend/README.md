# Backend Convex

Este backend contiene el esquema y funciones iniciales; la autorización se deriva de la identidad JWT verificada por Convex y del perfil asociado en la base de datos. No acepta un propietario o rol enviado por el cliente.

## Pruebas locales ejecutadas

```powershell
npm ci
npm test
npm run typecheck
```

Las pruebas usan `convex-test` con un runtime de pruebas en memoria. Cubren rechazo de usuarios no autenticados, aislamiento entre perfiles, estado bloqueado/vencido, deduplicación por `clientId` y auditoría de cambios hechos por el propietario.

## Configuración pendiente

No hay URL de despliegue, proveedor OIDC, secretos ni perfiles iniciales configurados. El CLI de Convex solicitó login y nombre del dispositivo en la sesión no interactiva, por lo que no se pudo probar un servidor real. No publiques credenciales ni habilites sincronización en la app hasta configurar un proveedor de identidad y ejecutar `npx convex codegen` en el despliegue elegido.

El cliente Flutter `dartvex` está aislado tras `ConvexSyncGateway`; no se marca conectividad ni sincronización activa mientras falten deployment URL y token de identidad.
