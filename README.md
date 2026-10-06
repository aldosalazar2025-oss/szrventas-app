# SRZ VENTAS

**Sistema de punto de venta (POS) móvil para Android y iPhone.**
Desarrollado por **Grupo Salazar**.

Versión: 2.0.1+3 · Hecho con Flutter · Funciona 100 % en el celular, sin servidor ni internet.

---

## ¿Qué es?

SRZ VENTAS es una app para vender desde el celular. Sirve para que un negocio pequeño registre sus ventas, controle su inventario e imprima tickets sin necesitar una computadora ni una caja registradora.

## ¿Para qué sirve?

- Cobrar rápido: escanear el producto, elegir el método de pago y listo.
- Saber cuánto hay en stock y cuánto se vendió.
- Entregar un ticket al cliente, impreso o por WhatsApp.
- Llevar el historial de ventas y sacar reportes en Excel.

## Funciones principales

**Ventas**
- Escáner de códigos de barras con la cámara.
- Venta por **unidad** o por **peso** (gramos/kilos).
- Descuento en **soles (S/)** o en **porcentaje (%)**; el descuento en % se recalcula si cambias el carrito.
- Métodos de pago: **Efectivo, Yape, Plin y Tarjeta**, con QR de Yape/Plin para que el cliente escanee.
- Monto recibido, botones rápidos de billetes y cálculo automático del **vuelto**.
- Nota opcional por venta.

**Productos e inventario**
- Productos con foto, precio de venta, precio de compra, stock y categoría.
- **Tallas y colores** (variantes con su propio stock y código de barras).
- **Tamaños** y **conjuntos de opciones** con precio extra (por ejemplo, tamaños o acompañamientos).
- Generación y exportación de **códigos de barras** (imagen y PDF).

**Tickets e impresión**
- Impresión en **impresora térmica Bluetooth** (papel de 58 mm u 80 mm).
- Ticket con nombre del negocio, dirección, teléfono, RUC y mensaje de pie personalizables.
- Compartir el ticket por **WhatsApp**.

**Control del negocio**
- **Historial de ventas** con detalle de cada venta.
- Exportación de ventas a **Excel**.
- **Vendedores** y **categorías** configurables.
- **Respaldo completo** (catálogo e imágenes) e importación en otro equipo.
- Símbolo de moneda configurable (por defecto S/).

## Cómo funciona

1. **Primera vez:** la app muestra la bienvenida y pide los datos básicos del negocio.
2. **Ajustes:** configura nombre, dirección, teléfono, RUC, métodos de pago, QR de Yape/Plin, vendedores e impresora.
3. **Inventario:** agrega tus productos (a mano o escaneando su código).
4. **Vender:** escanea o elige los productos, revisa la orden, aplica un descuento si quieres y elige el método de pago.
5. **Cobrar:** confirma la venta. Se descuenta el stock, se guarda en el historial y se imprime o comparte el ticket.

Todos los datos se guardan **en el dispositivo**. Haz respaldos con frecuencia desde Ajustes → Avanzado.

## Importante

Los tickets son comprobantes simples de venta. **No son boletas ni facturas** ni documentos vinculados a SUNAT. Para emitir comprobantes oficiales hay que usar los sistemas autorizados por la normativa peruana.

## Compilar

```bash
flutter pub get
flutter run                      # probar en el celular
flutter build apk --release      # generar el APK de Android
```

Para Android release se necesita `android/key.properties` y el archivo `.jks` (no se suben al repositorio). Para iPhone se puede generar el IPA con Codemagic (`codemagic.yaml`).

Permisos que usa: cámara (escáner), fotos (QR de Yape/Plin), Bluetooth (impresora) y ubicación para buscar impresoras Bluetooth.

## Créditos

Desarrollado por **Grupo Salazar**.
Soporte por WhatsApp: **+51 900 725 974**
