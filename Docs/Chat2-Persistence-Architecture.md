# Chat 2.0 Persistence Architecture

## Goal

Chat 2.0 treats a message as a persisted UI document instead of a text record that needs runtime merge.

This version is a greenfield redesign for the next-generation chat stack. It does not preserve compatibility with the current `content + attachments + blocks` model.

## Design Principles

1. `ChatMessage` only stores a structured document.
2. The database stores final snapshots, not merge patches.
3. Streaming state lives in memory only.
4. Tools output structured blocks directly.
5. Multi-device sync replaces message snapshots instead of merging local presentation fragments.

## Core Shift

Old model:

```swift
ChatMessage {
    content: String
    attachments: [ChatAttachment]
    blocks: [ChatMessageBlock]
}
```

New model:

```swift
ChatMessageRecord {
    documentData: Data
}
```

Where `documentData` encodes a fully structured message document:

```swift
ChatMessageDocument {
    nodes: [ChatMessageNode]
}
```

## Message Document

The message body is persisted as an ordered node list so inline placement becomes first-class:

```swift
[
    .text("今天推荐你去北京"),
    .block(.toolStatus(...)),
    .block(.mapRoute(...)),
    .text("然后再去吃饭"),
    .block(.restaurantCard(...))
]
```

This removes the need for:

- message-level `content`
- message-level `attachments`
- block merge from side channels
- `anchorToolCallID` as a patch-time insertion workaround

## Persistence Records

### ChatThreadRecord

- `id`
- `ownerAccountID`
- `title`
- `scenario`
- `memberID`
- `status`
- `createdAt`
- `updatedAt`
- `lastSyncedAt`

### ChatMessageRecord

- `id`
- `threadID`
- `clientMessageID`
- `serverMessageID`
- `role`
- `status` (`draft / streaming / committed / failed / tombstoned`)
- `documentData`
- `createdAt`
- `updatedAt`
- `committedAt`
- `errorText`
- `version`

`documentData` is the only source of truth for message presentation.

### ChatOutboxRecord

- `id`
- `messageID`
- `threadID`
- `requestEnvelopeData`
- `status` (`pending / inFlight / sent / failed`)
- `retryCount`
- `createdAt`
- `updatedAt`

### ChatSyncCheckpoint

- `scopeKey`
- `cursor`
- `updatedAt`

## Streaming Model

Streaming is intentionally not persisted as incremental patches.

```swift
StreamingMessageState {
    messageID
    threadID
    role
    nodes
    transientToolStates
    startedAt
}
```

Lifecycle:

1. Create a local draft message record with an empty document.
2. Keep streaming text and tool state in memory.
3. Append structured nodes in memory as tool results arrive.
4. Persist one committed snapshot when the assistant finishes.
5. If generation fails, persist a failure snapshot once.

This removes:

- polling the repository to wait for message readiness
- merge coordinators that patch streaming UI into the database
- duplicate writes to cache and persistence

## Tool to UI

Tools must return typed block payloads instead of display strings.

Old path:

```text
tool -> string -> attachment -> merge -> block
```

New path:

```text
tool -> typed payload -> message node -> final snapshot
```

Example:

```swift
.block(
    .init(
        id: toolCallID,
        payload: .sleepVisualization(
            .init(totalSleepMinutes: 450, deepSleepMinutes: 92, ...)
        )
    )
)
```

## Sync Semantics

Chat 2.0 uses immutable snapshots per message version.

Rules:

1. A committed message document is replaced as a whole.
2. A remote snapshot wins over any stale local committed snapshot.
3. Streaming state is never synced.
4. Tool status blocks are transient and should not appear in committed documents unless the product explicitly wants them in history.

## Database Shape

For Core Data, the minimum entity set becomes:

- `ChatThreadEntityV2`
- `ChatMessageEntityV2`
- `ChatOutboxEntityV2`
- `ChatSyncCheckpointEntityV2`

Recommended message attributes:

- `id: UUID`
- `threadID: UUID`
- `ownerAccountID: Int64`
- `clientMessageID: UUID`
- `serverMessageID: String?`
- `roleRaw: String`
- `statusRaw: String`
- `documentData: Binary`
- `errorText: String?`
- `version: Int32`
- `createdAt: Date`
- `updatedAt: Date`
- `committedAt: Date?`

## What Gets Deleted

The following patterns do not carry forward into Chat 2.0:

- `content`
- `attachmentsData`
- repository-level presentation patch merge
- `StructuredHealthCardMergeCoordinator`
- `ChatMergeEngine`
- attachment-first tool rendering
- database polling as an event mechanism

## Recommended Implementation Order

1. Add `ChatV2` domain models and persistence protocols.
2. Add new `ChatMessageEntityV2` and outbox/checkpoint entities.
3. Build a `ChatMessageDocumentCodec`.
4. Introduce a `StreamingMessageStateStore` that is memory only.
5. Implement a `ChatMessageSnapshotStore`.
6. Route one assistant tool flow end to end through Chat 2.0.
7. Move the rest of the send/sync pipeline over once one vertical slice is stable.

## First Vertical Slice

The safest first slice is:

- assistant text
- tool status
- sleep visualization
- final committed message snapshot

That path exercises:

- streaming
- inline block placement
- tool to typed block mapping
- one-shot persistence

without dragging every legacy block along at once.
