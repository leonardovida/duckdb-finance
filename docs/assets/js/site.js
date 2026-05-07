(() => {
  const navToggle = document.querySelector("[data-nav-toggle]");
  const sidebar = document.querySelector(".sidebar");

  if (navToggle && sidebar) {
    navToggle.addEventListener("click", () => {
      const isOpen = sidebar.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", String(isOpen));
    });
  }

  const content = document.querySelector(".content");
  const toc = document.querySelector("[data-toc]");

  if (content && toc) {
    const headings = [...content.querySelectorAll("h2, h3")].filter((heading) => heading.textContent.trim());
    headings.forEach((heading) => {
      if (!heading.id) {
        heading.id = heading.textContent
          .trim()
          .toLowerCase()
          .replace(/`/g, "")
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-|-$/g, "");
      }

      const link = document.createElement("a");
      link.href = `#${heading.id}`;
      link.textContent = heading.textContent.trim();
      link.dataset.level = heading.tagName === "H3" ? "3" : "2";
      toc.appendChild(link);
    });
  }

  document.querySelectorAll("pre").forEach((pre) => {
    const code = pre.querySelector("code");
    if (!code || pre.querySelector(".copy-code")) {
      return;
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy-code";
    button.textContent = "Copy";
    button.addEventListener("click", async () => {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = "Copy";
      }, 1200);
    });
    pre.appendChild(button);
  });

  const filter = document.querySelector("#function-filter");
  const count = document.querySelector("[data-reference-count]");
  const rows = [...document.querySelectorAll(".page-reference table tbody tr")];

  if (filter && rows.length) {
    const update = () => {
      const query = filter.value.trim().toLowerCase();
      let visible = 0;

      rows.forEach((row) => {
        const match = !query || row.textContent.toLowerCase().includes(query);
        row.hidden = !match;
        if (match) {
          visible += 1;
        }
      });

      if (count) {
        count.textContent = query ? `${visible} matching functions` : `${visible} documented functions`;
      }
    };

    filter.addEventListener("input", update);
    update();
  }
})();
