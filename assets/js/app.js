// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import "../css/app.css"

import "phoenix_html"
import socket from "./socket"
import Document from './document'


const addListener = (selector, event, fun) => {
  const elem = document.querySelector(selector);
  if (elem) elem.addEventListener(event, fun);
};


// Open existing document
addListener('#open-doc', 'submit', (e) => {
  e.preventDefault();
  const id = new FormData(e.target).get('id');
  const key = new FormData(e.target).get("key");
  window.location = `/${id}/${key}/`;
});

window.doc = new Document(socket);
