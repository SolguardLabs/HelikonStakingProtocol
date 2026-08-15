# Operación

## Arranque

```mermaid
flowchart LR
    A["Deploy Access"] --> T["Deploy tokens"]
    T --> B["Deploy registry"]
    B --> R["Deploy rewarder"]
    R --> P["Deploy reserve"]
    P --> V["Deploy vault"]
    V --> M["Deploy views and monitors"]
    M --> C["Configure roles and epochs"]
```

Todas las direcciones, roles y parámetros se verifican antes de abrir depósitos. El rewarder debe estar financiado antes de programar una emisión.

## Rutina de época

```mermaid
sequenceDiagram
    participant O as Operador
    participant R as Rewarder
    participant V as Vault
    participant S as Solvency
    O->>R: inspect budget and clock
    O->>V: read total weight
    O->>S: assess horizon
    S-->>O: coverage and severity
    O->>V: close current epoch
    V->>R: close with observed weight
```

Antes del cierre se comparan hora, presupuesto, emisión, peso, pagos y saldo. Después se archiva el índice final y se prepara la siguiente época.

## Pausas

```mermaid
stateDiagram-v2
    [*] --> Normal
    Normal --> DepositsPaused: capacity signal
    Normal --> BoostsPaused: weight signal
    Normal --> ExitsPaused: custody signal
    DepositsPaused --> Normal: reconciled
    BoostsPaused --> Normal: reconciled
    ExitsPaused --> Normal: reconciled
```

Las pausas se aplican por función. Una señal de recompensas suele detener boosts y nuevas entradas antes que salidas; una señal de custodia puede requerir detener salidas mientras se confirma el saldo.

## Recuperación

Conserva eventos y bloque, calcula obligaciones por posición, compara tokens, reproduce el índice y documenta cualquier diferencia. La reanudación requiere doble revisión y una evaluación de solvencia normal o expresamente aceptada.
