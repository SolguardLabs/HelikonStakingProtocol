# Integración

## Lecturas

`HelikonLens` ofrece tarjetas de posición y protocolo. Los consumidores deben tratar números como enteros sin signo y aplicar decimales del token únicamente en presentación.

```mermaid
flowchart LR
    UI["Aplicación"] --> L["HelikonLens"]
    L --> V["Vault"]
    UI --> M["Monitor"]
    M --> V
    UI --> S["SDK economics"]
    S --> D["Assessment"]
```

## Preparación de transacciones

```mermaid
sequenceDiagram
    participant U as Usuario
    participant A as Aplicación
    participant L as Lens
    participant V as Vault
    A->>L: read position card
    L-->>A: owner principal weights status
    A-->>U: quote and recipient
    U->>A: confirm
    A->>V: transaction
    V-->>A: event and receipt
    A->>L: refresh card
```

No construyas una transacción desde datos cacheados. Vuelve a leer propietario, principal, desbloqueo, nivel y estado inmediatamente antes de firmar.

## SDK económico

Las dataclasses son inmutables y validan rango `uint256`, orden de cobertura y consistencia entre fondos y pagos. `assess_portfolio` agrega grupos sin mezclar sus parámetros.

```mermaid
flowchart TD
    J["RPC snapshot"] --> N["Normalize integers"]
    N --> V{"Validate"}
    V -- no --> E["Integration error"]
    V -- sí --> A["assess solvency"]
    A --> P["Policy decision"]
    P --> O["Metrics and UI"]
```

## Eventos

Indexa apertura, activación, refresco, claim, retirada, financiación, programación y cierre de época. Una proyección local no sustituye al evento confirmado ni al estado del bloque finalizado.

## Reintentos

Las escrituras no se reenvían ciegamente. Ante un recibo ambiguo, consulta nonce, evento y estado antes de construir otra transacción. Los identificadores de posición deben tratarse como únicos en la red configurada.
