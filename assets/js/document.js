import Delta from "quill-delta";

export default class Document {
    editor = null; // DOM element reference
    channel = null; // Connected socket channel

    version = 0; // Local version
    contents = null; // Local contents
    committing = null; // Local change being currently pushed
    queued = null; // Pending change yet to be pushed

    constructor(socket) {
        const id = this.id = document.querySelector("#name").value;
        const key = this.key = document.querySelector("#key").value;

        this.channel = socket.channel(`doc:${id}`, { key });

        // Join document channel and set up event listeners
        this.channel
            .join()
            .receive("ok", () => {
                this.channel.on("open", (resp) => this.onOpen(resp));
                this.channel.on("update", (resp) =>
                    this.onRemoteUpdate(resp)
                );
                this.channel.on("update_user_permission", (resp) => this.onRemotePermUpdate(resp));
                this.channel.on("remove_user_permission", (resp) => this.onRemotePermRemove(resp));
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
        this.perm = perm;

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

        const newPosition = (this.perm > 0) ? remoteDelta.transformPosition(
            this.editor.getSelection()[0]
        ) : undefined;
        this.contents = this.contents.compose(remoteDelta);
        this.version += 1;
        this.updateEditor(newPosition);

        this.logState("UPDATED STATE");
    }

    onRemotePermUpdate({user, perm}) {
        if (user == this.key)
            location.reload();

        if (perm >= this.perm)
            return;

        let item = document.querySelector(`[data-user="${user}"]`);

        if (!item) {
            let list = document.querySelector("#perm-list");
            item = this.createPermItem(user, perm);
            list.appendChild(item);
        } else {
            this.updateSelect(item.querySelector("select"), false, perm);
        }
    }

    onRemotePermRemove({user}) {
        if (user == this.key)
            location.reload();

        let item = document.querySelector(`[data-user="${user}"`).remove();
    }

    save(e) {
        this.channel
            .push("save", {})
            .receive("ok", () => this.updateButton(e, "Saved!"))
            .receive("error", () => this.updateButton(e, "Error!"));
    }

    addPerm() {
        let user_key = document.querySelector("[name=new_user_key]").value;
        let new_perm = document.querySelector("[name=new_user_perm]").value;

        if (document.querySelector(`[data-user="${user_key}"]`)) {
            alert("Ese usuario ya tiene permiso!")
            return;
        }

        this.channel
            .push("update_user_permission", {user_key, new_perm})
            .receive("ok", () => {
                let list = document.querySelector("#perm-list");
                let new_item = this.createPermItem(user_key, new_perm);

                list.appendChild(new_item);
            })
            .receive("error", () => alert("Error al agregar un permiso"));
    }

    removePerm(user_key) {
        this.channel
            .push("remove_user_permission", {user_key})
            .receive("ok", () => {
                document.querySelector(`[data-user="${user_key}"]`).remove();
            })
            .receive("error", () => alert("Error al eliminar un permiso"));
    }

    updatePerm(select, user_key) {
        let last = select.dataset.lastValue;
        this.updateSelect(select, true)

        // setTimeout(() => {
            this.channel
                .push("update_user_permission", {user_key, new_perm: select.value})
                .receive("ok", () => this.updateSelect(select, false))
                .receive("error", () => this.updateSelect(select, false, last));
        // }, 1000);
    }

    // Flatten delta to plain text and display value in editor
    updateEditor(position) {
        this.editor.setMarkdown(
            this.contents.reduce((text, op) => {
                const val = typeof op.insert === "string" ? op.insert : "";
                return text + val;
            }, "")
        );

        if (position)
            this.editor.setSelection(position, position);
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

    createPermItem(user_key, perm) {
        let new_item = document.querySelector("#user-list-item").content.cloneNode(true);

        new_item.querySelector("h3").innerText = user_key;
        new_item.querySelector("li").dataset["user"] = user_key;
        new_item.querySelector("button").setAttribute("onclick", `doc.removePerm("${user_key}")`);

        let select = new_item.querySelector("select")
        select.value = perm;
        select.setAttribute("onchange", `doc.updatePerm(this, "${user_key}")`);

        return new_item;
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

    updateSelect(select, disabled, value) {
        select.disabled = disabled;
        if (value) {
            select.value = value;
        } else {
            select.dataset.lastValue = select.value;
        }
    }
}
