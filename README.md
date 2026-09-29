# SzrVentas

Aplicación móvil (Android) de punto de venta (POS) e inventario, pensada para negocios pequeños y medianos: tiendas, bodegas, boutiques de ropa y restaurantes.

## ¿Para qué sirve?

Permite llevar el control completo de un negocio desde el celular:

- Vender productos escaneando su código de barras o eligiéndolos desde un catálogo visual.
- Llevar el inventario al día (stock, precios, categorías, productos por peso, tallas/colores o tamaños con extras).
- Cobrar e imprimir el ticket de venta en una impresora térmica, o enviarlo por WhatsApp.
- Revisar el historial de ventas, con reportes y exportación a Excel.

## ¿Cómo funciona?

### 1. Vender (POS)
Desde la pantalla principal se abre la cámara para escanear el código de barras del producto, o se abre el catálogo para buscarlo y tocarlo directamente. Cada producto agregado aparece en el carrito con su cantidad y subtotal:

- **Productos por unidad:** se suman de uno en uno (o la cantidad que se indique).
- **Productos por peso** (ej. carnes, granos): se pide el peso en gramos/kilos y el precio se calcula automáticamente.
- **Productos con tallas y colores** (ej. ropa): al agregarlos se pide elegir la combinación específica (talla + color); el stock se descuenta de esa combinación puntual, no del total del producto.
- **Productos con tamaños y conjuntos** (ej. comida de restaurante): al agregarlos se pide elegir el tamaño (Personal, Mediana, Familiar, etc., cada uno con su propio precio) y, si aplica, los extras o cremas del conjunto configurado, cada uno con su precio adicional.

Con el carrito listo, se pasa a "Revisar Orden" para confirmar los productos, elegir el método de pago y cerrar la venta.

### 2. Cobrar e imprimir
Al finalizar la venta se genera el ticket, que se puede:
- Imprimir en una impresora térmica Bluetooth.
- Compartir como texto por WhatsApp.

El ticket incluye el detalle de cada producto, y cuando corresponde, la talla/color o el tamaño/extras elegidos.

### 3. Inventario
Desde la sección de inventario se crean y editan los productos: nombre, precio de compra y venta, stock, código de barras, categoría, foto, y el tipo de venta (unidad, peso, tallas/colores o tamaños/conjuntos). El stock se actualiza solo con cada venta.

### 4. Historial de ventas
Muestra todas las ventas realizadas, con el detalle de productos vendidos (incluyendo variantes), totales, ganancias y métodos de pago. Se puede exportar todo a un archivo Excel para llevar la contabilidad fuera de la app.

### 5. Configuración
Desde ajustes se personaliza el negocio (nombre, logo, moneda, métodos de pago) y se activan las funciones especiales según el tipo de negocio:
- **Tallas y colores:** para tiendas de ropa, con stock independiente por combinación.
- **Tamaños y variantes:** para restaurantes, con tamaños de precio variable y conjuntos de extras configurables.

Estas dos funciones son excluyentes entre sí: un negocio usa una u otra, según lo que venda.

## En resumen

SzrVentas cubre todo el ciclo de un negocio pequeño: **cargar el inventario → vender con o sin variantes → cobrar e imprimir → revisar lo vendido**, todo desde el celular y sin necesidad de conexión a internet para las operaciones del día a día.
