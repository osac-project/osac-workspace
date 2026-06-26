# MGMT-23568: Fulfillment API update mask clears unmasked spec fields

## Description
When updating a ComputeInstance via the fulfillment API with an update_mask targeting a single field (e.g., spec.restart_requested_at), all other explicit spec fields (cores, memory_gib, boot_disk, image, run_strategy) are cleared from the database.

Reproducibility: 100%

Steps to reproduce:
1. Create a ComputeInstance with all explicit spec fields
2. Update only restart_requested_at using update_mask: ["spec.restart_requested_at"]
3. Get the object — cores, memory_gib, boot_disk, image, run_strategy are gone

Expected: Only the masked field should change. Other fields preserved.
Actual: All unmasked spec fields are cleared.

Root cause: The masks.Path.Set() implementation likely replaces the entire spec message rather than setting only the leaf field when processing a nested path like spec.restart_requested_at. This causes unset fields in the input to overwrite populated fields in the existing object.

Impact: Blocks VM restart (MGMT-23329) from working end-to-end via the API. Affects any update-mask operation on ComputeInstance explicit spec fields.

## Comments
None

## Attachments
None
