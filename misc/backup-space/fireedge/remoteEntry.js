/* StorPool sidebar page for FireEdge 7.4.
   The script must load without throwing: Sunstone injects every remote
   before it draws, and a failed script stops the whole UI.
   The component is a React element built by hand ($$typeof), so this file
   does not bundle React. The iframe is the summary page from backup-space. */
(function () {
  function element(type, props) {
    return {
      $$typeof: Symbol.for("react.element"),
      type: type,
      key: null,
      ref: null,
      props: props,
      _owner: null,
    };
  }

  function StorPoolBackups() {
    return element("iframe", {
      title: "StorPool",
      src: "/storpool/api/ui",
      style: {
        display: "block",
        width: "100%",
        height: "calc(100vh - 7rem)",
        border: "0",
        background: "transparent",
      },
    });
  }

  window.StorpoolModule = {
    init: function () {},
    get: function (request) {
      if (request !== ".") {
        return Promise.reject(new Error("StorpoolModule has no " + request));
      }
      return Promise.resolve(function () {
        return { StorPoolBackups: StorPoolBackups };
      });
    },
  };
}());
