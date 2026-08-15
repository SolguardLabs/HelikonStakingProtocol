# Solvencia

## Dos reservas separadas

El principal de staking y el token de recompensa tienen obligaciones distintas. La solvencia de principal compara saldo del vault con principal total; la de recompensas compara fondos disponibles con emisión devengada y proyectada.

```mermaid
flowchart LR
    ST["Staking token balance"] --> PS["Principal solvency"]
    TP["Total principal"] --> PS
    RF["Rewards funded"] --> RS["Reward solvency"]
    RP["Rewards paid"] --> RS
    RE["Rewards emitted"] --> RS
    HE["Horizon emission"] --> RS
```

## Waterfall

```mermaid
flowchart TD
    A["Available rewards"] --> C["Coverage ratio"]
    L["Accrued liability"] --> P["Projected liability"]
    H["Horizon emission"] --> P
    P --> C
    C --> G["Capital gap"]
    G --> S["Severity"]
    W["Weight spread"] --> S
```

El nivel es crítico ante principal no solvente, déficit de capital o cobertura inferior al umbral crítico. Es alto ante cobertura inferior al mínimo o concentración de peso superior al límite; una banda del 75 % genera estado vigilado.

## Escenarios

| Escenario | Entrada | Lectura esperada |
| --- | --- | --- |
| base | 160 % cobertura | normal |
| concentración | spread 60 % | alto |
| agotamiento | fondos menores que obligación | crítico |
| principal | saldo inferior a depósitos | crítico |
| sin obligación | horizonte cero | cobertura no acotada |

```mermaid
quadrantChart
    title "Respuesta por cobertura y concentración"
    x-axis "Cobertura baja" --> "Cobertura alta"
    y-axis "Concentración baja" --> "Concentración alta"
    quadrant-1 "Reducir boosts"
    quadrant-2 "Revisar financiación"
    quadrant-3 "Pausar y recapitalizar"
    quadrant-4 "Operación normal"
    "Base": [0.82, 0.22]
    "Boost intenso": [0.76, 0.82]
    "Reserva baja": [0.18, 0.35]
```

## Uso

El controlador es observacional y registra la última evaluación. La política operativa decide pausas o financiación; el controlador no transfiere activos ni altera pesos.
