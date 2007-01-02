function OnBack()
{
	window.external.FinalBack();
}

function OnNext()
{
	var xml = window.external.Property("TransferManifest");
	var files = xml.selectNodes("transfermanifest/filelist/file");
	var form = document.getElementById('form1');

	for (i = 0; i < files.length; i++) {
		var postTag = xml.createNode(1, "post", "");
		postTag.setAttribute("href", "http://pr0n-internal.sesse.net/webdav/upload/");
		postTag.setAttribute("name", "image");

		// event
		if (form.existing.checked) {
			var dataTag = xml.createNode(1, "formdata", "");
			dataTag.setAttribute("name", "event");
			dataTag.text = "test"; //form.existingevent.value; FIXME
			postTag.appendChild(dataTag);
		} else {
			var dataTag = xml.createNode(1, "formdata", "");
			dataTag.setAttribute("name", "neweventid");
			dataTag.text = form.neweventid.value;
			postTag.appendChild(dataTag);
			
			dataTag = xml.createNode(1, "formdata", "");
			dataTag.setAttribute("name", "neweventdate");
			dataTag.text = form.neweventdate.value;
			postTag.appendChild(dataTag);
			
			dataTag = xml.createNode(1, "formdata", "");
			dataTag.setAttribute("name", "neweventdesc");
			dataTag.text = form.neweventdesc.value;
			postTag.appendChild(dataTag);
		}

		// who took this
		if (form.others.checked) {
			var dataTag = xml.createNode(1, "formdata", "");
			dataTag.setAttribute("name", "takenby");
			dataTag.text = form.other.value;
			postTag.appendChild(dataTag);
		}
		
		// original file size (to avoid the evil resizing)
		dataTag = xml.createNode(1, "formdata", "");
		dataTag.setAttribute("name", "size");
		dataTag.text = files.item(i).getAttribute("size");
		postTag.appendChild(dataTag);
	
		files.item(i).appendChild(postTag);
	}

	var uploadTag = xml.createNode(1, "uploadinfo", "");
	var htmluiTag = xml.createNode(1, "htmlui", "");
	htmluiTag.text = "http://pr0n.sesse.net/test/";
	uploadTag.appendChild(htmluiTag);
	
	/*var target = xml.createNode(1, "target", "");
	target.setAttribute("href", "https://pr0n-internal.sesse.net/webdav/upload/test/");
	uploadTag.appendChild(target); */

	xml.documentElement.appendChild(uploadTag);
	window.external.FinalNext();
}

function OnCancel()
{
	alert('OnCancel');
}

function somethingchanged()
{
	var valid = true;
	var form = document.getElementById('form1');
	var disable_existingevent, disable_newevent;

	if (form.existing.checked) {
		disable_existingevent = false;
		disable_newevent = true;

		if (form.existingevent.value == '') {
			valid = false;
		}
	} else {
		disable_existingevent = true;
		disable_newevent = false;

		// this matches 1:1 the checks done on the server
		var id = form.neweventid.value;
		var date = form.neweventdate.value;
		var desc = form.neweventdesc.value;
		
		if (id.match(/^\s*$/) || !id.match(/^([a-zA-Z0-9-]+)$/)) {
			valid = false;
		}
		if (date.match(/^\s*$/) || date.match(/[<>&]/) || date.length > 100) {
			valid = false;
		}
		if (desc.match(/^\s*$/) || desc.match(/[<>&]/) || desc.length > 100) {
			valid = false;
		}
	}

	// enable/disable the "existing event" form
	form.existingevent.disabled = disable_existingevent;
	
	var extexts = getElementsByClass(document, 'existingeventtext', '*');
	for (i = 0; i < extexts.length; ++i) {
		extexts[i].style.color = disable_existingevent ? 'gray' : '';
	}

	// enable/disable the "new event" form
	form.neweventid.disabled = disable_newevent;
	form.neweventdate.disabled = disable_newevent;
	form.neweventdesc.disabled = disable_newevent;

	var netexts = getElementsByClass(document, 'neweventtext', '*');
	for (i = 0; i < netexts.length; ++i) {
		netexts[i].style.color = disable_newevent ? 'gray' : '';
	}

	// and finally, the "who" form
	var disable_who;
	if (form.me.checked) {
		disable_who = true;
	} else {
		disable_who = false;
	
		var who = form.other.value;
		if (who.match(/^\s*$/) || who.match(/[<>&]/) || who.length > 100) {
			valid = false;
		}
	}

	form.other.disabled = disable_who;

	var whotexts = getElementsByClass(document, 'whotext', '*');
	for (i = 0; i < whotexts.length; ++i) {
		whotexts[i].style.color = disable_who ? 'gray' : '';
	}


	window.external.SetWizardButtons(true, valid, false);
}

function getElementsByClass(node,searchClass,tag) {
	var classElements = new Array();
	var els = node.getElementsByTagName(tag);
	var elsLen = els.length;
	for (i = 0, j = 0; i < elsLen; i++) {
		if (els[i].className == searchClass) {
			classElements[j] = els[i];
			j++;
		}
	}
	return classElements;
}

somethingchanged();
