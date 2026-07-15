# Protocol Buffer Conventions

Proto definitions live in `fulfillment-service`. Read [`fulfillment-service/docs/API.md`](../../fulfillment-service/docs/API.md) before adding or modifying any `.proto` file — it is the authoritative source for all API conventions (object structure, naming, services, request/response patterns, REST transcoding, enums, conditions, references, and documentation requirements).

OSAC follows [Kubernetes API conventions](https://github.com/kubernetes/community/blob/main/contributors/devel/sig-architecture/api-conventions.md) adapted for protobuf.

## Workflow

- Always run `buf lint` from `fulfillment-service/` before committing proto changes
- Regenerate code by running `buf generate` from `fulfillment-service/` after proto changes
- `SERVICE_SUFFIX` lint rule is intentionally excluded in `buf.yaml`
