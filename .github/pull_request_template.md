## Summary

- What changed?
- Why was this needed?

## Related Issues

- Closes #
- Related #

## Validation

- [ ] `xcodebuild -project APKInstaller.xcodeproj -scheme APKInstaller -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- [ ] `xcodebuild -project APKInstaller.xcodeproj -scheme APKInstaller -configuration Debug -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test`
- [ ] Added/updated tests where needed
- [ ] Updated docs where behavior changed

## Screenshots (UI changes only)

- Before:
- After:

## Checklist

- [ ] No hardcoded personal machine paths or sibling-repo dependencies
- [ ] No secrets/certificates/provisioning files committed
- [ ] Changes are scoped and do not include unrelated refactors
