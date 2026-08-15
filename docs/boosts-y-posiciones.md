# Boosts y posiciones

## Posición

Una posición conserva propietario, principal, peso base, peso contable, multiplicador, nivel, ventanas temporales, índice pagado, recompensa pendiente y estado.

```mermaid
stateDiagram-v2
    [*] --> ActiveBase
    ActiveBase --> ActiveBoosted: activar nivel
    ActiveBoosted --> ActiveBase: refrescar expiración
    ActiveBase --> ActiveBase: salida parcial
    ActiveBoosted --> ActiveBoosted: salida parcial
    ActiveBase --> Closed: salida total
    ActiveBoosted --> Closed: salida total
    Closed --> [*]
```

## Activación

```mermaid
sequenceDiagram
    participant U as Usuario
    participant V as Vault
    participant R as Rewarder
    participant B as Registry
    participant P as Reserve
    U->>V: activate boost
    V->>R: sync
    V->>V: accrue position
    V->>B: require active tier
    V->>P: transfer fee
    V->>V: replace accounting weight
```

La política comprueba principal mínimo y máximo, duración, espera desde el final anterior y tarifa. El peso nuevo reemplaza al anterior; no se suma como una posición adicional.

## Salida temprana

La penalización lineal depende del importe, tiempo restante y horizonte anual:

```text
penalty = amount × remaining / 365 days / 5
received = amount - penalty
```

El usuario suministra un máximo aceptable para protegerse de cambios temporales entre simulación y ejecución.

```mermaid
flowchart LR
    A["Amount"] --> P["Penalty quote"]
    U["Unlock at"] --> P
    N["Now"] --> P
    P --> C{"Penalty <= max"}
    C -- sí --> R["Reserve credit"]
    C -- sí --> T["Transfer net"]
    C -- no --> X["Revert"]
```

## Operadores

El propietario puede aprobar un operador global o uno por posición. La autorización no cambia la titularidad y puede revocarse. Los clientes deben mostrar siempre receptor e importe neto antes de firmar.
