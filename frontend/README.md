# Bookstore Frontend

Interfaz React ligera para interactuar con los microservicios del diagrama (catálogo, carrito y órdenes). Usa Vite y se alimenta de las URLs expuestas por los Network Load Balancers internos desplegados en AWS.

## Variables de entorno

Configura los endpoints en un archivo `.env` dentro de esta carpeta:

```ini
VITE_CATALOG_API=https://internal-catalog-nlb-XXXX.elb.amazonaws.com
VITE_CART_API=https://internal-cart-nlb-YYYY.elb.amazonaws.com
VITE_ORDER_API=https://internal-order-nlb-ZZZZ.elb.amazonaws.com
```

> Sugerencia: el ALB público que define Terraform puede inyectar estas variables en tiempo de arranque del launch template.

## Scripts

```bash
npm install
npm run dev      # Desarrollo con hot reload
npm run build    # Compila para producción
npm run preview  # Sirve el build generado
```

## Funcionalidad

- Consulta el catálogo vía `GET /catalog`.
- Añade productos al carrito demo (`POST /cart/{userId}/items`).
- Lanza un checkout (`POST /cart/{userId}/checkout`).
- Crea una orden invocando `POST /orders` con el carrito actual.

Todo el flujo utiliza el usuario `demo-user`. 