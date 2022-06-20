import Delta from "quill-delta";

export default class Document {
    editor = null; // DOM element reference
    channel = null; // Connected socket channel

    version = 0; // Local version
    contents = null; // Local contents
    committing = null; // Local change being currently pushed
    queued = null; // Pending change yet to be pushed

    usersPermissions = null;

    constructor(socket) {
        const id = document.querySelector("#name").value;
        const key = document.querySelector("#key").value;
        this.channel = socket.channel(`doc:${id}`, { key });

        // Join document channel and set up event listeners
        this.channel
            .join()
            .receive("ok", () => {
                this.channel.on("open", (resp) => this.onOpen(resp));
                this.channel.on("update", (resp) =>
                    this.onRemoteUpdate(resp)
                );
            })
            .receive("error", (resp) => {
                console.log("Socket Error", resp);
            });
    }

    initEditor() {
        const Editor = toastui.Editor;
        const { codeSyntaxHighlight } = Editor.plugin;


        const editor = new Editor({
          el: document.querySelector('#editor'),
          height: '500px',
          initialEditType: 'wysiwyg',
          previewStyle: 'vertical',
          usageStatistics: false,
          plugins: [codeSyntaxHighlight]
        });

        editor.eventEmitter.listen(
            editor.eventEmitter.eventTypes.keyup,
            () => this.onLocalUpdate(editor.getMarkdown())
        );

        return editor;
    }

    initViewer() {
        const Editor = toastui.Editor;
        const { codeSyntaxHighlight } = Editor.plugin;

        const viewer = Editor.factory({
            el: document.querySelector("#editor"),
            viewer: true,
            height: "500px",
            usageStatistics: false,
            plugins: [codeSyntaxHighlight]
        });

        viewer.preview.previewContent.style.border = "1px solid gray";
        viewer.preview.previewContent.style.padding = "1em 2em";

        return viewer;
    }

    // Show initial contents on joining the document channel
    onOpen({ contents, version, perm }) {
        this.editor = (perm == 0) ? this.initViewer() : this.initEditor();

        this.logState("CURRENT STATE");

        this.version = version;
        this.contents = new Delta(contents);
        this.updateEditor();

        this.logState("UPDATED STATE");
    }

    // Track and push local changes
    onLocalUpdate(value) {
        this.logState("CURRENT STATE");

        const newDelta = new Delta().insert(value);
        const change = this.contents.diff(newDelta);

        this.contents = newDelta;
        this.pushLocalChange(change);
        this.logState("UPDATED STATE");
    }

    pushLocalChange(change) {
        if (this.committing) {
            // Queue new changes if we're already in the middle of
            // pushing previous changes to server
            this.queued = this.queued || new Delta();
            this.queued = this.queued.compose(change);
        } else {
            const version = this.version;
            this.version += 1;
            this.committing = change;

            // setTimeout(() => {
            this.channel
                .push("update", { change: change.ops, version })
                .receive("ok", (resp) => {
                    console.log("ACK RECEIVED FOR", version, change.ops);
                    this.committing = null;

                    // Push any queued changes after receiving ACK
                    // from server
                    if (this.queued) {
                        this.pushLocalChange(this.queued);
                        this.queued = null;
                    }
                });
            // }, 2000);
        }
    }

    // Listen for remote changes
    onRemoteUpdate({ change, version }) {
        this.logState("CURRENT STATE");
        console.log("RECEIVED", { version, change });

        let remoteDelta = new Delta(change);

        // Transform remote delta if we're in the middle
        // of pushing changes
        if (this.committing) {
            remoteDelta = this.committing.transform(remoteDelta, false);

            // If there are more queued changes the server hasn't seen
            // yet, transform both remote delta and queued changes on
            // each other to make the document consistent with server.
            if (this.queued) {
                const remotePending = this.queued.transform(remoteDelta, false);
                this.queued = remoteDelta.transform(this.queued, true);
                remoteDelta = remotePending;
            }
        }

        const newPosition = remoteDelta.transformPosition(
            this.editor.selectionStart
        );
        this.contents = this.contents.compose(remoteDelta);
        this.version += 1;
        this.updateEditor(newPosition);

        this.logState("UPDATED STATE");
    }

    save(e) {
        this.channel
            .push("save", {})
            .receive("ok", () => this.updateButton(e, "Saved!"))
            .receive("error", () => this.updateButton(e, "Error!"));
    }

    // Flatten delta to plain text and display value in editor
    updateEditor(position) {
        this.editor.setMarkdown(
            this.contents.reduce((text, op) => {
                const val = typeof op.insert === "string" ? op.insert : "";
                return text + val;
            }, "")
        );

        if (position) {
            this.editor.selectionStart = position;
            this.editor.selectionEnd = position;
        }
    }

    logState(msg) {
        console.log(msg, {
            version: this.version,
            contents:
                this.contents &&
                this.contents.ops[0] &&
                this.contents.ops[0].insert,
        });
    }

    updateButton(button, text) {
        const prevText = button.innerText;

        button.disabled = true;
        button.classList.add("button-outline");
        button.innerText = text;

        setTimeout(() => {
            button.innerText = prevText;
            button.classList.remove("button-outline");
            button.disabled = false;
        }, 1500);
    }
}
