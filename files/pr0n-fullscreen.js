var req;

function init_ajax()
{
	req = false;

	if (window.XMLHttpRequest) {
		// Mozilla/Safari
		try {
			req = new XMLHttpRequest();
		} catch(e) {
			req = false;
		}
	} else if (window.ActiveXObject) {
		// IE/Windows
		try {
			req = new ActiveXObject("Msxml2.XMLHTTP");
		} catch(e) {
			try {
				req = new ActiveXObject("Microsoft.XMLHTTP");
			} catch(e) {
				req = false;
			}
		}
	}
}

function find_width()
{
	if (typeof(window.innerWidth) == 'number') {
		// non-IE
		return [window.innerWidth, window.innerHeight];
	} else if (document.documentElement && (document.documentElement.clientWidth || document.documentElement.clientHeight)) {
		// IE 6+ in 'standards compliant mode'
		return [document.documentElement.clientWidth, document.documentElement.clientHeight];
	} else if (document.body && (document.body.clientWidth || document.body.clientHeight)) {
		// IE 4-compatible
		return [document.body.clientWidth, document.body.clientHeight];
	}
	return [null,null];
}

/*
 * pr0n can resize to any size we'd like, but we're much more likely
 * to have this set of fixed-resolution screens cached, so to increase
 * performance, we round down to the closest fit and use that.
 */
function reduce_to_fixed_width(size)
{
	var fixed_sizes = [
		[ 1280, 960 ],
		[ 1024, 768 ],
		[ 800, 600 ],
		[ 640, 480 ],
		[ 512, 384 ],
		[ 320, 256 ],
		[ 240, 192 ],
		[ 120, 96 ],
		[ 80, 64 ]
	];
	for (i = 0; i < fixed_sizes.length; ++i) {
		if (size[0] >= fixed_sizes[i][0] && size[1] >= fixed_sizes[i][1])
			return fixed_sizes[i];
	}
	return [ 80, 64 ];
}
	
function display_image(width, height, evt, filename, element_id)
{
	var url = "http://" + global_vhost + "/" + evt + "/" + width + "x" + height + "/" + filename;
	var img = document.getElementById(element_id);
	if (img != null) {
		img.src = "";
		img.parentNode.removeChild(img);
	}

	img = document.createElement("img");
	img.id = element_id;
	img.alt = "";

	if (img.src != url) {
		img.src = url;
	}
	
	var main = document.getElementById("iehack");
	main.appendChild(img);

	return img;
}

function prepare_preload(img, width, height, evt, filename)
{
	// cancel any pending preload
	var preload = document.getElementById("preload");
	if (preload != null) {
		preload.src = "";
		preload.parentNode.removeChild(preload);
	}

	// grmf -- IE doesn't fire onload if the image was loaded from cache, so check for
	// completeness first; should at least be _somewhat_ better
	if (img.complete) {
		display_image(width, height, evt, filename, "preload");
	} else {
		img.onload = function() { display_image(width, height, evt, filename, "preload"); };
	}	
}

function relayout()
{
	var size = find_width();
	var adjusted_size = reduce_to_fixed_width(size);

	var img = display_image(adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num], "image");
	if (can_go_next()) {
		prepare_preload(img, adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num + 1]);
	}
	
	// center the image on-screen
	var main = document.getElementById("main");
	main.style.position = "absolute";
	main.style.left = (size[0] - adjusted_size[0]) / 2 + "px";
	main.style.top = (size[1] - adjusted_size[1]) / 2 + "px"; 
	main.style.width = adjusted_size[0] + "px";
	main.style.height = adjusted_size[1] + "px";
	main.style.lineHeight = adjusted_size[1] + "px"; 

	set_opacity("previous", can_go_previous() ? 0.7 : 0.1);
	set_opacity("next", can_go_next() ? 0.7 : 0.1);
	set_opacity("close", 0.7);
}

function set_opacity(id, amount)
{
	var elem = document.getElementById(id);
	if (typeof(elem.style.opacity) != 'undefined') {            // W3C
		elem.style.opacity = amount;
	} else if (typeof(elem.style.mozOpacity) != 'undefined') {  // older Mozilla
		elem.style.mozOpacity = amount;
	} else if (typeof(elem.style.filter) != 'undefined') {      // IE
		if (elem.style.filter.indexOf("alpha") == -1) {
			// add an alpha filter if there isn't one already
			if (elem.style.filter) {
				elem.style.filter += " ";
			} else {
				elem.style.filter = "";
			}
			elem.style.filter += "alpha(opacity=" + (amount*100.0) + ")";
		} else {	
			// ugh? this seems to break in color index mode...
			if (typeof(elem.filters) == 'unknown') {
				elem.style.filter = "alpha(opacity=" + (amount*100.0) + ")";
			} else {
				elem.filters.alpha.opacity = (amount * 100.0);
			}
		}
	} else {                             // no alpha support
		if (amount > 0.5) {
			elem.style.visibility = "visible";
			elem.style.zorder = 1;
		} else {
			elem.style.visibility = "hidden";
		}
	}
}

function can_go_previous()
{
	return (global_image_num > 0);
}

function go_previous()
{
	if (!can_go_previous())
		return;

	--global_image_num;

	var adjusted_size = reduce_to_fixed_width(find_width());

	var img = display_image(adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num], "image");
	if (can_go_previous()) {
		set_opacity("previous", 0.7);
		prepare_preload(img, adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num - 1]);
	} else {
		set_opacity("previous", 0.1);
	}
	set_opacity("next", can_go_next() ? 0.7 : 0.1);
}

function can_go_next()
{
	return (global_image_num < global_image_list.length - 1);
}

function go_next()
{
	if (!can_go_next())
		return;

	++global_image_num;

	var adjusted_size = reduce_to_fixed_width(find_width());

	var img = display_image(adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num], "image");
	if (can_go_next()) {
		set_opacity("next", 0.7);
		prepare_preload(img, adjusted_size[0], adjusted_size[1], global_evt, global_image_list[global_image_num + 1]);
	} else {
		set_opacity("next", 0.1);
	}
	set_opacity("previous", can_go_previous() ? 0.7 : 0.1);
}

function key_down(which)
{
	if (which == 39) {   // right
		if (can_go_next()) {
			set_opacity("next", 0.99);
		}
	} else if (which == 37) {   // left
		if (can_go_previous()) {
			set_opacity("previous", 0.99);
		}
	} else if (which == 27) {   // escape
		set_opacity("close", 0.99);
	}
}

function key_up(which) {
	if (which == 39) {   // right
		if (can_go_next()) {
			set_opacity("next", 0.7);
			go_next();
		}
	} else if (which == 37) {   // left
		if (can_go_previous()) {
			set_opacity("previous", 0.7);
			go_previous();
		}
	} else if (which == 27) {   // escape
		set_opacity("close", 0.7);
		do_close();
	} else if (which == 32 && global_select) {   // space
		select_image(global_image_list[global_image_num]);
	}
}

function select_image(filename)
{
	if (!req)
		return;

	draw_text("Selecting " + filename + "...");
	
	req.open("POST", "http://" + global_vhost + "/select", false);
	req.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
	req.send("mode=single&event=" + global_evt + "&filename=" + filename);

	setTimeout("fade_text(0.99)", 30);
}

function fade_text(opacity)
{
	set_opacity("text", opacity);
	if (opacity > 0.0) {
		opacity -= 0.03;
		if (opacity < 0.0)
			opacity = 0.0;
		setTimeout("fade_text(" + opacity + ")", 30);
	} else {
		var text = document.getElementById("text");
		if (text != null) {
			text.parentNode.removeChild(text);
		}
	}
}

function do_close()
{
	window.location = global_return_url;
}

function draw_text(msg)
{
	// remove any text we might have left
	var text = document.getElementById("text");
	if (text != null) {
		text.parentNode.removeChild(text);
	}

	text = document.createElement("p");
	text.id = "text";
	text.style.position = "absolute";
	text.style.color = "white";
	text.style.lineHeight = "24px";
	text.style.font = "24px verdana, arial, sans-serif";
	text.innerHTML = msg;

	var main = document.getElementById("main");
	main.appendChild(text);

	text.style.left = (main.clientWidth - text.clientWidth) / 2 + "px";
	text.style.top = (main.clientHeight - text.clientHeight) / 2 + "px";
}

// enable the horrible horrible IE PNG hack
function ie_png_hack()
{
	var vstr = navigator.appVersion.split("MSIE");
	var v = parseFloat(vstr[1]);
	if (v >= 5.5 && v < 7.0 && document.body.filters) {
		var next = document.getElementById("next");
		next.outerHTML = "<span id=\"next\" style=\"display: inline-block; position: absolute; bottom: 0px; right: 0px; width: 50px; height: 50px; filter:progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + next.src + "')\" onmousedown=\"if (can_go_next()) set_opacity('next', 1.0)\" onmouseup=\"if (can_go_next()) { set_opacity('next', 0.7); go_next(); }\" onmouseout=\"if (can_go_next()) { set_opacity('next', 0.7); }\" />";
		
		var previous = document.getElementById("previous");
		previous.outerHTML = "<span id=\"previous\" style=\"display: inline-block; position: absolute; bottom: 0px; right: 0px; width: 50px; height: 50px; filter:progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + previous.src + "')\" onmousedown=\"if (can_go_previous()) set_opacity('previous', 1.0)\" onmouseup=\"if (can_go_previous()) { set_opacity('previous', 0.7); go_previous(); }\" onmouseout=\"if (can_go_previous()) { set_opacity('previous', 0.7); }\" />";
		
		var close = document.getElementById("close");
		close.outerHTML = "<span id=\"close\" style=\"display: inline-block; position: absolute; top: 0px; right: 0px; width: 50px; height: 50px; filter:progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + close.src + "')\" onmousedown=\"set_opacity('close', 1.0)\" onmouseup=\"set_opacity('close', 0.7); do_close();\" onmouseout=\"set_opacity('close', 0.7);\" />";
	}
}
