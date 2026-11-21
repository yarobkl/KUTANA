#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -frontend -parse $(find iOS -name '*.swift' -print)
swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift Tests/domain_smoke.swift -o /tmp/kutana-domain-smoke
/tmp/kutana-domain-smoke
swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift iOS/KUTANA/Core/Domain/Drafts.swift iOS/KUTANA/Core/Networking/Backend.swift iOS/KUTANA/Core/Networking/AuthService.swift Tests/network_smoke.swift -o /tmp/kutana-network-smoke
/tmp/kutana-network-smoke

swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift iOS/KUTANA/Core/Domain/Drafts.swift iOS/KUTANA/Core/Networking/Backend.swift Tests/drafts_smoke.swift -o /tmp/kutana-drafts-smoke
/tmp/kutana-drafts-smoke

swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift iOS/KUTANA/Core/Domain/Drafts.swift iOS/KUTANA/Core/Networking/Backend.swift iOS/KUTANA/Core/Networking/AccessTokenMetadata.swift Tests/chat_smoke.swift -o /tmp/kutana-chat-smoke
/tmp/kutana-chat-smoke
