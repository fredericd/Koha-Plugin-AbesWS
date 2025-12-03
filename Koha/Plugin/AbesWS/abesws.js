(function( jQuery, undefined ) {

// Configuration locales
let c;
let proxy;
let idAutorite = "";
let remoteClientExist = false;
let oFrame;
let idrefinit = false;


let kohaCloneField = window.CloneField;
window.CloneField = function(args) {
  const idPrev = arguments[0];
  kohaCloneField(args);

  c.idref.catalog.fields_array.forEach(function(tag) {
    const divs = $(`[id^=div_indicator_tag_${tag}]`);
    for (let i=0; i < divs.length; i++) {
      (function(){
        const div = $(divs.get(i));
        const button = div.find('a.popupIdRef');
        button.click(function(e) { onClick(e, div); });
      })();
    }
  });

};

let current = {
  tag: '',
  id: '',
  set: (letter, value) => {
    const subid = current.id.substr(0, 6);
    $(`#tag_${current.tag}_${current.id} [id^=tag_${current.tag}_subfield_${letter}_${subid}]`).val(value)
  },
  get: (letter) => {
    const subid = current.id.substr(0, 6);
    return $(`#tag_${current.tag}_${current.id} [id^=tag_${current.tag}_subfield_${letter}_${subid}]`).val();
  }
};

const serializer = {
  stringify: function(data) {
    let message = "";
    for (let key in data) {
      if (data.hasOwnProperty(key)) {
        message += key + "=" + escape(data[key]) + "&";
      }
    }
    return message.substring(0, message.length - 1);
  },
  parse: function(message) {
    const data = {};
    let d = message.split("&");
    let pair, key, value;
    for (let i = 0, len = d.length; i < len; i++) {
      pair = d[i];
      key = pair.substring(0, pair.indexOf("="));
      value = pair.substring(key.length + 1);
      data[key] = unescape(value);
    }
    return data;
  }
};

function initClient() {

  // Rend la fenêtre déplaçable
  // $("#popupContainer").draggable();

  if (remoteClientExist) {
    showPopWin("", screen.width*0.7, screen.height*0.6, null);
    return 0;
  }

  showPopWin("", screen.width*0.7, screen.height*0.6, null);
  remoteClientExist = true;
  if (document.addEventListener) {
    window.addEventListener("message", function(e) {
      traiteResultat(e);
    });
  }
  else {
    window.attachEvent('onmessage', function(e) {
      traiteResultat(e);
    });
  }
  return 0;
}

function escapeHtml(texte) {
  return texte
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function parseMarcHeading(xml) {
  const fields = [];
  const withNewline = xml.indexOf("\n") > 0 ? true : false;
  while (1) {
    let pos = xml.indexOf('<datafield tag="2');
    if (pos === -1) break;
    xml = xml.substring(withNewline ? pos+40 : pos+39);
    pos = xml.indexOf('</datafield>');
    let raw = xml.substring(0, pos-3);
    xml = xml.substring(pos+3);
    raw = raw.replaceAll('><', ">\n<");
    const lines = raw.split("\n");
    const field = {};
    lines.forEach((line) => {
      pos = line.indexOf('code=');
      const letter = line.substr(pos+6, 1);
      let value = line.substr(pos+9);
      pos = value.indexOf('<');
      value = value.substr(0, pos);
      field[letter] = value;
    });
    fields.push(field);
  }
  let returnId = 0;
  if ( fields.length == 0 ) {
    return;
  } else if (fields.length == 2) {
    fields.forEach((field, i) => {
      let lang = field[7];
      if (lang) {
        lang = lang.substr(4,2);
        if (lang === 'ba') {
          returnId = i;
        }
      }
    });
  }
  return fields[returnId];
}

function traiteResultat(e) {
  let data = e.data;
  data = serializer.parse(data);

  const ppn = data.b;
  if (ppn === undefined) return;
  current.set('3', ppn);

  const field = parseMarcHeading(data.f);
  if (c.marcflavour === 'MARC21') {
    // Regroupement nom/prénom
    if (field.b && field.b.length > 0) {
      field.a = field.a + ', ' + field.b;
      delete field.b;
    }
  }
  ['a','b','c','d','e','f','g','h','p'].forEach((letter) => {
    const value = field[letter] || '';
    if (value) current.set(letter, value);
  });

  hidePopWin(null);
  $('#toolbar.sticky').css('position', 'sticky');
  $('#toolbar.sticky').css('z-index', '999');
}

function onClick(e, div) {
  const idtop = div.attr('id');
  const tag = idtop.substr(18, 3);
  current.tag = tag;
  current.id = idtop.substr(22);

  $('#toolbar.sticky').css('position', 'relative');
  $('#toolbar.sticky').css('z-index', '-1');
  let index = 'Nom de personne';
  if (c.marcflavour === 'MARC21') {
    if (tag === '110' || tag === '710') index = 'Nom de collectivité';
  } else {
    if (tag == '601' || tag == '710' || tag == '711' || tag == '712' ) index = 'Nom de collectivité';
    if (tag == '602') index = 'Famille';
  }
  let value = current.get('3');
  if (value) {
    index = 'Identifiant IdRef (n°PPN)';
  } else {
    value = current.get('a') + ' ' + current.get('b');
    value = value.replace(/'/g, "\\\'");
  }

  const { idclient } = c.idref;
  let ymd = new Date().toISOString().split('T')[0].replace(/-/g, '');
  const message = {
    Index1: index,
    Index1Value: value,
    fromApp: idclient,
    'z686_a': idclient,
    'z686_c': idclient,
    'z686_2': ymd,
  };

  let auttag =
    (tag == '710' || tag == '711' || tag == '712') ? '210' :
    '200'
  message[`z${auttag}_a`] = current.get('a');
  message[`z${auttag}_b`] = current.get('b');
  message[`z${auttag}_f`] = current.get('f');

  // 200$a : 200$e / 200$f, 200$g, 210 $d
  const racine = '[id^=tag_200_subfield_';
  let title = [];
  const append = (where, prefix) => {
    const v = value = $(where).val();
    if (v) {
      if (prefix) title.push(prefix);
      title.push(v);
    }
  };
  append('[id^=tag_200_subfield_a');
  append('[id^=tag_200_subfield_e', ' e ');
  append('[id^=tag_200_subfield_f', ' / ');
  append('[id^=tag_200_subfield_g', ' / ');
  append('[id^=tag_214_subfield_d', ', ');
  append('[id^=tag_210_subfield_d', ', ');
  message.z810_a = 'Auteur de : ' + title.join('');

  let lang = $('[id^=tag_100_subfield_a_').val();
  lang = lang.substr(22,3);
  message.z101_a = lang;

  if (initClient()==0) {};

  oFrame = document.getElementById("popupFrame");
  if (!idrefinit) {
    oFrame.contentWindow.postMessage(serializer.stringify({Init:"true"}), "*");
    idrefinit = false;
  }

  oFrame.contentWindow.postMessage(serializer.stringify(message), "*");

  e.preventDefault();
}


function pageCatalog() {
  // On charge les éléments externes
  $('head').append('<link rel="stylesheet" type="text/css" href="/api/v1/contrib/abesws/static/subModal.css">');
  window.gDefaultPage = c.idref.url;
  $.getScript("/api/v1/contrib/abesws/static/subModal.js")
   .done(() => {
   });
  c.idref.catalog.fields_array.forEach(function(tag) {
    const divs = $(`[id^=div_indicator_tag_${tag}]`);
    for (let i=0; i < divs.length; i++) {
      (function(){
        const div = $(divs.get(i));
        const button = $("<a href='#' class='popupIdRef'><img src='/api/v1/contrib/abesws/static/img/idref-short.svg' style='max-height: 24px;'/></a>");
        div.append(button);
        button.click((e) => onClick(e, div));
      })();
    }
  });
}


function getBibsFromPpn(ppn, cb) {
  const url = c.url.api + "/multiwhere/" + ppn + '&format=text/json';
  jQuery.getJSON(url)
    .done((data) => {
      let bibs = data?.sudoc?.query?.result?.library;
      if (!Array.isArray(bibs)) bibs = [ bibs ];
      const bibPerRcr = c.iln.rcr_hash;
      bibs.forEach((bib) => {
        bib.itsme = bibPerRcr[bib.rcr] ? true : false;
        bib.sortname = bib.itsme ? ' ' + bib.shortname : bib.shortname;
      });
      bibs = bibs.sort((a, b) => a.sortname.localeCompare(b.sortname));
      cb(bibs);
    });
}

function pageDetail() {
  const ppn = $(c.detail.ppn_selector).text();
  if (ppn === '') {
    console.log('PPN non trouvé. Manque-t-il le sélecteur PPN ?');
    return;
  }
  $('.nav.nav-tabs').append(`
    <li role="presentation">
      <a
		class="nav-link"
		href="#idref_panel"
		id="idref-tab"
		data-tabname="idref"
		aria-controls="idref_panel"
		role="tab"
		data-bs-toggle="tab"
		data-bs-target="#idref_panel"
		aria-selected="true"
	  >
        <span>AbesWS</span>
      </a>
    </li>
  `);
  $('#bibliodetails .tab-content').append(`
    <div class="tab-pane" id="idref_panel" role="tabpanel" aria-labelledby="idref-tab" tabindex="0"> 
      <div id="abes-content">
        <div id="abes-publications"></div>
        <div id="abes-qualimarc"></div>
      </div>
    </div>
  `);
  if ( c.detail.location ) {
    getBibsFromPpn(ppn, (bibs) => {
      let html = '<div style="padding-top:10px;">' +
      '<h4><img src="https://www.sudoc.abes.fr/htdocs/psi_images/img_psi/3.0/icons/sudoc.png"/> Localisation</h4>' +
      '<ul>' +
      bibs.map((bib) => {
        let style = bib.itsme
          ? "background: green; color: white;"
          : '';
        let shortname = '<a href="http://www.sudoc.abes.fr/cbs/xslt//DB=2.1/SET=1/TTL=1/CLK?IKT=8888&TRM='
          + bib.rcr + '" target="_blank" style="' + style + '">' + bib.shortname + '</a>';
        return '<li>' + shortname + '</li>'
      }).join('') +
      '</ul></div>';
      $('#abes-publications').html(html);
    });
  }
  if (c.detail.qualimarc.enabled) {
    const url = `${c.url.qualimarc}/check`;
    const query = `{
      "ppnList": ["${ppn}"],
      "typeAnalyse":"${c.detail.qualimarc.analyse}"
    }`;
    $.ajax(url, {
      data: query,
      contentType: 'application/json',
      type: 'POST'
    }).done(function(res) {
      let html = `
        <div style="padding-top:10px;">
          <h4>QualiMarc</h3>`;
      if (res.ppnErrones.length > 0) {
        const erreurs = res.resultRules[0].detailerreurs.sort((a, b) => {
          const aa = a.priority + a.zones[0];
          const bb = b.priority + b.zones[0];
          return aa.localeCompare(bb);
        });
        html += `
          <table>
            <thead>
              <tr>
                <td>Zone</td>
                <td>Avertissement</td>
                <td>Priorité</td>
              </tr>
            </thead>
            <tbody>`;
        erreurs.forEach(err => {
          html += `
            <tr>
              <td>${err.zones.join(' / ')}</td>
              <td>${err.message}</td>
              <td>${err.priority}</td>
            </tr>`;
        });
        html += '</tbody></table>';
      } else {
        html += "<p>Notice sans erreur</p>";
      }
      html += "</div>";
      $('#abes-qualimarc').html(html);
    });
  }
}


function opacDetail() {
  const { opac } = c.idref;
  $('span.idref-link').each(function(index){
    const ppn = $(this).attr('ppn');
    const html = `
      <a class="idref-link-click" style="cursor: pointer;" ppn="${ppn}" title="${opac.text.tab}">
        ${opac.text.trigger}
      </a>`;
    $(this).html(html);
  });
  $('.idref-link-click').click(function(){
    const ppn = $(this).attr('ppn');
    const url = `/api/v1/contrib/abesws/idref/${ppn}`;
    jQuery.getJSON(url)
      .done((infos) => {
        let html;
        if (infos === '') {
          html = 'Auteur non trouvé dans IdRef';
        } else {
          html = '';
          if (opac.info.enabled && infos.name) {
            html = `
              <h2>
                ${infos.name} / <small>
                <a href="https://www.idref.fr/${infos.ppn}" target="_blank">${infos.ppn}</a>
                </small>
              </h2>`;
            if (infos.altnames) {
              html += `
                <div style="font-size:100%; margin-bottom: 3px;">
                  ${infos.altnames.join(' · ')}
                </div>`;
            }
            if (infos.notes) {
              html += `
                <div style="font-size:100%; margin-bottom: 3px;">
                  ${infos.notes.join('<br/>')}
                </div>`;
            }
          }
          if (opac.toid.enabled && infos?.altid && Object.keys(infos.altid).length > 0) {
            const { altid } = infos;
            const ok = opac.toid.source;
            const sources = Object.keys(altid).filter(source => ok[source]);
            if (sources.length > 0 ) {
              html += `
                <h2 style="margin-top: 15px;">Identifiants externes</h2>
                <ul>`;
              sources.forEach((source) => {
                const id = altid[source];
                const url =
                  source == 'GEOVISTORY' ? `https://www.geovistory.org/page/${id}` :
                  source == 'HAL'        ? `https://cv.hal.science/${id}` :
                  source == 'ISNI'       ? `http://isni.org/isni/${id}` :
                  source == 'ORCID'      ? `https://orcid.org/${id}` :
                  source == 'PRELIB'     ? `https://mshb.huma-num.fr/prelib/${id}` :
                  source == 'RNSR'       ? `https://appliweb.dgri.education.fr/rnsr/PresenteStruct.jsp?numNatStruct=${id}&PUBLIC=OK` :
                  source == 'WIKIDATA'   ? `https://www.wikidata.org/wiki/${id}` :
                    id;
                html += `<li>${source}: <a href="${url}" target="_blank">${id}</a></li>`;
              });
              html += '</ul>\n';
            }
          }
          if (opac.publication.enabled) {
            const navig = infos.roles.map(role => `<a href="#idref-role-${role.code}" style="font-size: 90%;">${role.label} (${role.docs.length})</a>`);
            html += `
              <h2>Publications</h2>
              <div style="margin-top: 0px; margin-bottom: 5px;";>${navig.join(' • ')}</div>`;
            infos.roles.forEach((role) => {
              html += `
                <h3 id="idref-role-${role.code}">${role.label}</h3>
                <table class="table table-striped table-hover table-sm"><tbody>`;
              role.docs.forEach((doc) => {
                html += `
                  <tr>
                    <td>
                    <a href="https://www.sudoc.fr/${doc.ppn}" target="_blank" rel="noreferrer">
                    <img title="Publications dans le Sudoc" src="/api/v1/contrib/abesws/static/img/sudoc.png" />
                    </a>`;
                if (doc.bib) {
                  html += `
                    <a href="/cgi-bin/koha/opac-detail.pl?biblionumber=${doc.bib}" target="_blank">
                    <img title="Publications dans la catalogue local" src="/opac-tmpl/bootstrap/images/favicon.ico" />
                    </a>`;
                }
                html += `</td><td>${doc.citation}</td></tr>`;
              });
              html += '</tbody></table>';
            });
            html += '</div>';
          }
        }
        const idrefDiv = $('#idref-infos');
        if (idrefDiv.length) {
          idrefDiv.html(html);
        } else {
          html = `<div id="idref-infos">${html}</div>`;
          $('.nav-tabs').append(`
            <li id="tab_idref" class="nav-item" role="presentation">
             <a href="#idref-infos_panel"
                class="nav-link"
                id="idref-infos-tab"
                data-bs-toggle="tab"
                data-bs-target="#idref-infos_panel"
                aria-controls="idref-infos_panel"
                role="tab"
                aria-selected="false"
                tabindex="-1"
             >
               ${opac.text.tab}
             </a>
            </li>
          `);
          $('#bibliodescriptions .tab-content').append(`
            <div id="idref-infos_panel" class="tab-pane" role="tabpanel" aria-labelledby="tab_idref-tab">
              ${html}
            <div>
          `);
        }
        showBsTab("bibliodescriptions", "idref-infos");
        $([document.documentElement, document.body]).animate({
          scrollTop: $("#idref-infos").offset().top
        }, 2000);
      });
    });
}


function run(conf) {
  c = conf;
  if (c?.idref?.catalog?.enabled && $('body').is("#cat_addbiblio")) {
    pageCatalog();
  } else if (c?.detail?.enabled && $('body').is("#catalog_detail")) {
    pageDetail();
  }
  if ($('body').is('#opac-detail') && c?.idref?.opac?.enabled)  {
    opacDetail();
  }
}

$.extend({
  abesWs: (c) => run(c),
});


})( jQuery );
