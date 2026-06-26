# MGMT-23638: Public VirtualNetwork API rejects creation due to missing region field

## Description
Public VN API delegates to private server without setting default region, causing all Create calls to fail with: field spec.region is required.

Fix: set region to default in the public server Create method before delegating.

## Comments
None

## Attachments
None
