# Protocol Buffer Conventions

Proto definitions live in `fulfillment-service`. The `osac-operator` consumes generated types via gRPC client for the feedback loop — naming and structure conventions here apply when reading or writing these types in any repo.

## Naming

- **Files**: `snake_case` (e.g., `virtual_network_type.proto`)
- **Messages**: `PascalCase` (e.g., `VirtualNetwork`)
- **Fields**: `snake_case` (e.g., `ipv4_cidr`)
- **Enums**: `SCREAMING_SNAKE_CASE` (e.g., `STATE_PENDING`)
- **Services/RPCs**: `PascalCase` (e.g., `VirtualNetworks`, `CreateVirtualNetwork`)

## API Structure

```text
fulfillment-service/proto/public/osac/public/v1/    # Public API (user-facing, read-heavy)
fulfillment-service/proto/private/osac/private/v1/  # Private API (admin, full CRUD + Signal RPC)
Each resource has:
├── <resource>_type.proto         # Resource schema definition
└── <resource>s_service.proto     # CRUD service operations
```

## Type File Pattern

- Resource message with metadata (id, name, labels, annotations)
- Status enum (Pending, Ready, Failed)
- Spec fields (resource-specific configuration)
- Status fields (observed state)

## Service File Pattern

- Create/Get/List/Update/Delete RPC methods
- HTTP annotations for REST gateway (`google.api.http`)
- OpenAPI annotations for documentation
- Private services add Signal RPC (no HTTP endpoint)

## Field Guidelines

- Use `optional` for fields that may not be set (e.g., IPv6 CIDR in dual-stack)
- Omit `optional` for always-present fields (even if empty string/0)
- Use `google.protobuf.FieldMask` for partial updates
- Use `string` fields for resource ID references
- Use buf.build validation annotations

## List Operations

Include SQL-like filtering: `page`, `size`, `filter` (WHERE syntax), `order` (ORDER BY syntax).

## Workflow

- Always run `buf lint` before committing proto changes
- Regenerate code with `buf generate` after proto changes
- `SERVICE_SUFFIX` lint rule is intentionally excluded in `buf.yaml`
- OpenAPI specs at `fulfillment-service/openapi/v2/openapi.json` and `v3/openapi.yaml`
