# Gobernanza

## Roles

La autoridad se divide entre gobierno, guardián, operador de recompensas y riesgo. El relevo administrativo usa una cuenta pendiente y aceptación explícita.

```mermaid
flowchart TB
    G["Governor"] --> C["Configuration"]
    H["Guardian"] --> P["Pauses"]
    R["Reward operator"] --> E["Epochs and funding"]
    K["Risk"] --> S["Solvency policy"]
    C --> D["Delayed activation"]
    E --> D
    S --> D
```

## Propuesta

Toda modificación incluye valor anterior y nuevo, unidad, contratos, hipótesis, escenarios de cobertura, época de activación y reversión.

```mermaid
sequenceDiagram
    participant P as Proponente
    participant R as Riesgo
    participant T as Revisión técnica
    participant O as Operaciones
    P->>R: parámetros y simulaciones
    R-->>P: dictamen
    P->>T: cambio versionado
    T-->>O: artefacto aprobado
    O->>O: activar en época acordada
    O-->>R: conciliación posterior
```

## Cambios sensibles

- duración, tasa y presupuesto de época;
- multiplicador, tarifa y renovación de niveles;
- umbrales de cobertura y concentración;
- pausas, roles y direcciones de módulos;
- retirada de reservas y recuperación de activos.

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Simulated
    Simulated --> Approved
    Approved --> Timelocked
    Timelocked --> Executed
    Executed --> Reconciled
    Reconciled --> [*]
    Executed --> RolledBack: threshold breach
    RolledBack --> Reconciled
```

## Emergencias

El guardián puede contener actividad dentro de sus permisos. La medida se documenta, caduca y recibe revisión posterior. No se cambian saldos ni se retira reserva como parte automática de una pausa.

## Evidencia

Se conserva propuesta, simulación, aprobaciones, commit, bytecode, resultado de automatización, transacción, bloque, eventos y conciliación. Las etiquetas publicadas son inmutables.
