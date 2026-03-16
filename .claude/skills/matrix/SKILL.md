---
name: matrix
description: Send messages, listen to messages, manage rooms, and interact with Matrix chat via matrix-commander-rs. Use when user asks to send a message, check Matrix, read messages, or manage Matrix rooms.
allowed-tools: Bash(matrix-commander-rs:*), Bash(tmux:*)
---

# Matrix Chat

Interact with the user's Matrix homeserver using `matrix-commander-rs`.

## Prerequisites

- Credentials are stored locally after first login (no auth needed on subsequent runs)
- If credentials are missing, the CLI will error — run login interactively in a tmux pane:
  ```bash
  tmux split-window -h "matrix-commander-rs --login password --homeserver https://matrix.glinq.org --user-login mloeper; read"
  ```

## Sending Messages

```bash
# Send a plain text message to a specific room
matrix-commander-rs --message "Hello!" --room '!roomid:matrix.glinq.org'

# Send a Markdown-formatted message
matrix-commander-rs --message "**Bold** and _italic_" --markdown --room '!roomid:matrix.glinq.org'

# Send an HTML message
matrix-commander-rs --message "<h1>Title</h1><p>Body</p>" --html --room '!roomid:matrix.glinq.org'

# Send as notice (bot-style, less prominent)
matrix-commander-rs --message "Status update" --notice --room '!roomid:matrix.glinq.org'

# Send a file
matrix-commander-rs --file /path/to/file.pdf --room '!roomid:matrix.glinq.org'
```

## Reading Messages

**Known bug:** `--listen tail` and `--tail` crash or fail with room IDs containing `!` due to an escaping bug. Use `--listen once` with room aliases instead.

```bash
# Get all queued messages from a room (use room alias, not ID)
matrix-commander-rs --listen once --room '#onlyhackers:matrix.glinq.org' --timeout 10

# Include your own messages (recommended for full chat history)
matrix-commander-rs --listen once --listen-self --room '#onlyhackers:matrix.glinq.org' --timeout 10

# Wait for a new message to arrive, then query to read it
# Step 1: block until a message arrives
matrix-commander-rs --listen once --room '#onlyhackers:matrix.glinq.org' --timeout 120
# Step 2: query again to actually read the message content
matrix-commander-rs --listen once --listen-self --room '#onlyhackers:matrix.glinq.org' --timeout 10
```

## Room Management

```bash
# List all rooms
matrix-commander-rs --rooms

# List only joined rooms
matrix-commander-rs --joined-rooms

# Get room info
matrix-commander-rs --get-room-info '!roomid:matrix.glinq.org'

# Get joined members of a room
matrix-commander-rs --joined-members '!roomid:matrix.glinq.org'

# Create a new room
matrix-commander-rs --room-create my-room-alias --name "Room Name" --topic "Room topic"

# Join a room
matrix-commander-rs --room-join '!roomid:matrix.glinq.org'

# Invite a user
matrix-commander-rs --room-invite '!roomid:matrix.glinq.org' --user '@user:matrix.glinq.org'

# Enable encryption in a room
matrix-commander-rs --room-enable-encryption '!roomid:matrix.glinq.org'
```

## Account Info

```bash
# Print your user ID
matrix-commander-rs --whoami

# List your devices
matrix-commander-rs --devices

# Get your profile
matrix-commander-rs --get-profile

# Get/set display name
matrix-commander-rs --get-display-name
matrix-commander-rs --set-display-name "New Name"
```

## Output Formats

Use `--output` to control output format:
- `text` — human-readable (default)
- `json` — JSON output for programmatic processing
- `json-spec` — JSON with full spec fields

```bash
matrix-commander-rs --tail 5 --room '!roomid:matrix.glinq.org' --output json
```

## Defaults

- **Homeserver:** `https://matrix.glinq.org`
- **Default room:** OnlyHackers (`!abqXsTxtuSwElxvHoH:matrix.glinq.org`) — use this when the user doesn't specify a room

## Important Notes

- **Room IDs** use the format `!roomid:matrix.glinq.org` — always quote them in the shell (single quotes) because `!` is special in bash
- **User IDs** use the format `@username:matrix.glinq.org`
- **Interactive commands** (login, verify) must be run in a tmux pane since they require user input
- **Verification:** To verify the device, run in tmux:
  ```bash
  tmux split-window -h "matrix-commander-rs --verify emoji; read"
  ```
  Then confirm emojis on another verified Matrix client.
- When the user asks to send a message without specifying a room, ask which room to use
- When sending multi-line or complex messages, prefer `--markdown` for formatting
