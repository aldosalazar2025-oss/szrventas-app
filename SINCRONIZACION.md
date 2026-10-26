# Sincronización por Wi-Fi (Android ⇄ PC)

Ajustes → **Sincronización**. Necesita el Panel SZR Ventas con la conexión iniciada
y ambos equipos en la misma red Wi-Fi.

1. En la PC: Ajustes → Sincronización → **Iniciar conexión** (muestra IP y código).
2. Aquí: escribe IP y código → **Conectar con la PC**.
3. **Sincronizar todo**: primero envía las ventas pendientes y luego descarga productos,
   precios, categorías, fotos y existencias (así el stock recibido ya incluye tus ventas).
4. **Actualizar productos** / **Enviar ventas a la PC** hacen cada parte por separado.
5. **Ver ventas pendientes** y **Ver estado de conexión** muestran qué falta y los errores.

Una venta solo se marca como sincronizada cuando la PC la confirma. Si se corta la conexión
sigue pendiente y no se duplica al reintentar. Con la app abierta y emparejada, revisa la PC
cada 8 segundos y sincroniza sola si hay ventas pendientes o cambios.

Las ventas hechas antes de actualizar esta versión se marcan como "previas" y NO se envían
(su stock ya estaba contado en la PC).

## Compilar
```
flutter pub get
flutter build apk --release
```
Sin dependencias nuevas.
