(function() {

var global_disabled_opacity = 0.1;
var global_default_opacity = 0.7;
var global_highlight_opacity = 1.0;
var global_infobox = true;

function find_width()
{
	var dpr = find_dpr();
	return [window.innerWidth * dpr, window.innerHeight * dpr];
}

function find_dpr()
{
	return window.devicePixelRatio || 1;
}

/*
 * pr0n can resize to any size we'd like, but we're much more likely
 * to have this set of fixed-resolution screens cached, so to increase
 * performance, we round down to the closest fit and use that. This 
 * function is a pessimal estimate of what thumbnail size we can _always_
 * fit on the screen -- it's right if and only if all images are 4:3
 * (and landscape). If individual size information is available, use
 * pick_image_size, below.
 */
var fixed_sizes = [
	[ 3840, 2880 ],
	[ 3200, 2400 ],
	[ 2800, 2100 ],
	[ 2304, 1728 ],
	[ 2048, 1536 ],
	[ 1920, 1440 ],
	[ 1600, 1200 ],
	[ 1400, 1050 ],
	[ 1280, 960 ],
	[ 1152, 864 ],
	[ 1024, 768 ],
	[ 800, 600 ],
	[ 640, 480 ],
	[ 512, 384 ],
	[ 320, 256 ],
	[ 240, 192 ],
	[ 120, 96 ],
	[ 80, 64 ]
];
function max_image_size(screen_size)
{
	var i;
	for (i = 0; i < fixed_sizes.length; ++i) {
		if (screen_size[0] >= fixed_sizes[i][0] && screen_size[1] >= fixed_sizes[i][1]) {
			return fixed_sizes[i];
		}
	}
	return [ 80, 64 ];
}

function pick_image_size(screen_size, image_size)
{
	var i;
	for (i = 0; i < fixed_sizes.length; ++i) {
		// this is a duplicate of pr0n's resizing code, hope for no floating-point
		// inaccuracies :-)
		var thumbxres = fixed_sizes[i][0];
		var thumbyres = fixed_sizes[i][1];
		var width = image_size[0];
		var height = image_size[1];

		if (!(thumbxres >= width && thumbyres >= height)) {
			var sfh = width / thumbxres;
			var sfv = height / thumbyres;
			if (sfh > sfv) {
				width  /= sfh;
				height /= sfh;
			} else {
				width  /= sfv;
				height /= sfv;
			}
			width = Math.floor(width);
			height = Math.floor(height);
		}

		if (screen_size[0] >= width && screen_size[1] >= height) {
			// be sure _not_ to return a reference
			return [ fixed_sizes[i][0], fixed_sizes[i][1], width, height ];
		}
	}
	return [ 80, 64 ];
}

function replace_image_element(url, element_id, parent_node)
{
	var img = document.getElementById(element_id);
	if (img !== null) {
		if (img.src === url) {
			return img;
		}
		img.parentNode.removeChild(img);
	}

	img = document.createElement("img");
	img.id = element_id;
	img.alt = "";
	img.src = url;
	parent_node.appendChild(img);
	return img;
}

function rename_element(old_name, new_name)
{
	// Remove any element that's in the way.
	var elem = document.getElementById(new_name);
	if (elem !== null) {
		elem.parentNode.removeChild(elem);
	}

	elem = document.getElementById(old_name);
	if (elem !== null) {
		elem.id = new_name;
	}
	return elem;
}

function display_image(width, height, evt, filename, element_id)
{
	var url = window.location.origin + "/" + evt + "/" + width + "x" + height + "/" + filename;
	var main = document.getElementById("iehack");
	var preload = document.getElementById("preload");
	var dpr = find_dpr();
	var img;
	// See if we have a preload going on that we can reuse.
	if (element_id == "image" && preload !== null && preload.src == url) {
		rename_element("preload_box", "image_box");
		img = rename_element("preload", "image");
	} else {
		img = replace_image_element(url, element_id, main);
	}
	img.style.position = "absolute";
	img.style.left = "0px";
	img.style.top = "0px";
	img.style.transformOrigin = "top left";
	img.style.transform = "scale(" + (1.0 / dpr) + ")";

	if (element_id == "image") {
		// Update the "download original" link.
		var original_url = window.location.origin + "/" + evt + "/original/" + filename;
		document.getElementById("origdownload").href = original_url;

		// If it's a raw image, show a JPEG link.
		var fulldownload = document.getElementById("fulldownload");
		if (filename.match(/\.(nef|cr2)$/i)) {
			fulldownload.style.display = "block";
			var full_url = window.location.origin + "/" + evt + "/" + filename;
			document.getElementById("fulldownloadlink").href = full_url;
			origdownload.innerHTML = "Download original image (RAW)";
		} else {
			fulldownload.style.display = "none";
			origdownload.innerHTML = "Download original image";
		}
	}

	if (global_infobox) {
		var url;
		if (dpr == 1) {
			url = window.location.origin + "/" + evt + "/" + width + "x" + height + "/box/" + filename;
		} else {
			url = window.location.origin + "/" + evt + "/" + width + "x" + height + "@" + dpr.toFixed(2) + "/box/" + filename;
		}
		var boximg = replace_image_element(url, element_id + "_box", main);

		boximg.style.position = "absolute";
		boximg.style.left = "0px";
		boximg.style.bottom = "-1px";
		boximg.style.transformOrigin = "bottom left";
		boximg.style.transform = "scale(" + (1.0 / dpr) + ")";
	} else {
		var boximg = document.getElementById(element_id + "_box");
		if (boximg !== null) {
			boximg.parentNode.removeChild(boximg);
		}
	}

	return img;
}

function display_image_num(num, element_id)
{
	var screen_size = find_width();
	var adjusted_size;

	if (global_image_list[num][2] == -1) {
		// no size information, use our pessimal guess
		adjusted_size = max_image_size(screen_size);
	} else {
		adjusted_size = pick_image_size(screen_size, [ global_image_list[num][2], global_image_list[num][3] ]);
	}

	var img = display_image(adjusted_size[0], adjusted_size[1], global_image_list[num][0], global_image_list[num][1], element_id);
	
	if (element_id == "image") {
		// we want to shrink the box as much as possible if we know the true
		// size of the image
		center_image(num);
		
		// replace the anchor part (if any) with the image number
		window.location.hash = "#" + (num+1);
	}

	return img;
}

function prepare_preload(img, num)
{
	// cancel any pending preload
	var preload = document.getElementById("preload");
	if (preload !== null) {
		preload.parentNode.removeChild(preload);
	}
	
	var preload_box = document.getElementById("preload_box");
	if (preload_box !== null) {
		preload_box.parentNode.removeChild(preload_box);
	}

	// grmf -- IE doesn't fire onload if the image was loaded from cache, so check for
	// completeness first; should at least be _somewhat_ better
	if (img.complete) {
		display_image_num(num, "preload");
	} else {
		img.onload = function() { display_image_num(num, "preload"); };
	}	
}

function can_go_next()
{
	return (global_image_num < global_image_list.length - 1);
}

function can_go_previous()
{
	return (global_image_num > 0);
}

function set_opacity(id, amount)
{
	var elem = document.getElementById(id);

	// If optionmenu is visible, options is also visible.
	if (id === "options" && amount < 0.7) {
		var optionmenu = document.getElementById("optionmenu");
		if (optionmenu.style.display === "block") {
			amount = 0.7;
		}
	}
	elem.style.opacity = amount;
}

function center_image(num)
{
	var screen_size = find_width();
	var dpr = find_dpr();
	var width, height;
	
	if (global_image_list[num][2] == -1) {
		// no size information, use our pessimal guess
		var adjusted_size = max_image_size(screen_size);
		width = adjusted_size[0];
		height = adjusted_size[1];
	} else {
		// use the exact information
		var adjusted_size = pick_image_size(screen_size, [ global_image_list[num][2], global_image_list[num][3] ]);
		width = adjusted_size[2];
		height = adjusted_size[3];
	}

	// center the image on-screen
	var main = document.getElementById("main");
	main.style.position = "absolute";
	main.style.left = (((screen_size[0] - width) / 2) / dpr) + "px";
	main.style.top = (((screen_size[1] - height) / 2) / dpr) + "px";
	main.style.width = (width / dpr) + "px";
	main.style.height = (height / dpr) + "px";
	main.style.lineHeight = (height / dpr) + "px";
}

function relayout()
{
	var img = display_image_num(global_image_num, "image");
	if (can_go_next()) {
		prepare_preload(img, global_image_num + 1);
	}

	set_opacity("previous", can_go_previous() ? global_default_opacity : global_disabled_opacity);
	set_opacity("next", can_go_next() ? global_default_opacity : global_disabled_opacity);
	set_opacity("close", global_default_opacity);
	set_opacity("options", global_default_opacity);
}

function go_previous()
{
	if (!can_go_previous()) {
		return;
	}

	var img = display_image_num(--global_image_num, "image");
	if (can_go_previous()) {
		set_opacity("previous", global_default_opacity);
		prepare_preload(img, global_image_num - 1);
	} else {
		set_opacity("previous", global_disabled_opacity);
	}
	set_opacity("next", can_go_next() ? global_default_opacity : global_disabled_opacity);
}

function go_next()
{
	if (!can_go_next()) {
		return;
	}

	var img = display_image_num(++global_image_num, "image");
	if (can_go_next()) {
		set_opacity("next", global_default_opacity);
		prepare_preload(img, global_image_num + 1);
	} else {
		set_opacity("next", global_disabled_opacity);
	}
	set_opacity("previous", can_go_previous() ? global_default_opacity : global_disabled_opacity);
}

function do_close()
{
	if (global_image_num > 0) {
		window.location = global_return_url + '#' + (global_image_num + 1);
	} else {
		window.location = global_return_url;
	}
}

function toggle_optionmenu()
{
	var optionmenu = document.getElementById("optionmenu");
	if (optionmenu.style.display === "block") {
		optionmenu.style.display = "none";
	} else {
		optionmenu.style.display = "block";
		set_opacity("options", 0.7);
	}
}
window['toggle_optionmenu'] = toggle_optionmenu;

function draw_text(msg)
{
	// remove any text we might have left
	var text = document.getElementById("text");
	if (text !== null) {
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

function fade_text(opacity)
{
	set_opacity("text", opacity);
	if (opacity > 0.0) {
		opacity -= 0.03;
		if (opacity < 0.0) {
			opacity = 0.0;
		}
		setTimeout(function() { fade_text(opacity); }, 30);
	} else {
		var text = document.getElementById("text");
		if (text !== null) {
			text.parentNode.removeChild(text);
		}
	}
}

function select_image(evt, filename, selected)
{
	if (selected) {
		draw_text("Selecting " + filename + "...");
	} else {
		draw_text("Unselecting " + filename + "...");
	}
	
	var req = new XMLHttpRequest();
	req.open("POST", window.location.origin + "/select", false);
	req.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
	req.send("event=" + evt + "&filename=" + filename + "&selected=" + selected);

	setTimeout(function() { fade_text(0.99); }, 30);
}

function key_down(which)
{
	if (which == 39) {   // right
		if (can_go_next()) {
			set_opacity("next", global_highlight_opacity);
		}
	} else if (which == 37) {   // left
		if (can_go_previous()) {
			set_opacity("previous", global_highlight_opacity);
		}
	} else if (which == 27) {   // escape
		set_opacity("close", global_higlight_opacity);
	} else {
		check_for_hash_change();
	}
}

function key_up(which) {
	if (which == 39) {   // right
		if (can_go_next()) {
			set_opacity("next", global_default_opacity);
			go_next();
		}
	} else if (which == 37) {   // left
		if (can_go_previous()) {
			set_opacity("previous", global_default_opacity);
			go_previous();
		}
	} else if (which == 27) {   // escape
		set_opacity("close", global_default_opacity);
		do_close();
	} else if (which == 32 && global_select) {   // space
		select_image(global_image_list[global_image_num][0], global_image_list[global_image_num][1], 1);
	} else if (which == 85 && global_select) {   // u
		select_image(global_image_list[global_image_num][0], global_image_list[global_image_num][1], 0);
	} else {
		check_for_hash_change();
	}
}

function parse_image_num(default_value) {
	var num = parseInt(window.location.hash.substr(1));
	if (num >= 1 && num <= global_image_list.length) {  // and then num != NaN
		return (num - 1);
	} else {
		return default_value;
	}
}
window['parse_image_num'] = parse_image_num;

function check_for_hash_change() {
	var num = parse_image_num(-1);
	if (num != -1 && num != global_image_num) {
		global_image_num = num;
		relayout();
	}
}

function toggle_immersive() {
	if (global_default_opacity == 0.7) {
		global_disabled_opacity = 0.0;
		global_default_opacity = 0.0;
		global_highlight_opacity = 0.2;
		global_infobox = false;
		document.getElementById('immersivetoggle').innerHTML = 'Show decorations';
	} else {
		global_disabled_opacity = 0.1;
		global_default_opacity = 0.7;
		global_highlight_opacity = 1.0;
		global_infobox = true;
		document.getElementById('immersivetoggle').innerHTML = 'Hide all decorations';
	}
	relayout();
}
window['toggle_immersive'] = toggle_immersive;

window.onload = function() {
	relayout();
	setInterval(check_for_hash_change, 1000);

	var body = document.body;
	body.onresize = function() { relayout(); };
	body.onkeydown = function() { key_down(event.keyCode); };
	body.onkeyup = function() { key_up(event.keyCode); };
	body.onhashchange = function() { check_for_hash_change(); };
	body.onclick = function() { check_for_hash_change(); };

	var previous = document.getElementById('previous');
	previous.onmousedown = function() { if (can_go_previous()) { set_opacity('previous', global_highlight_opacity); } };
	previous.onmouseup = function() { if (can_go_previous()) { set_opacity('previous', global_default_opacity); go_previous(); } };
	previous.onmouseout = function() { if (can_go_previous()) { set_opacity('previous', global_default_opacity); } };

	var next = document.getElementById('next');
	next.onmousedown = function() { if (can_go_next()) { set_opacity('next', global_highlight_opacity); } };
	next.onmouseup = function() { if (can_go_next()) { set_opacity('next', global_default_opacity); go_next(); } };
	next.onmouseout = function() { if (can_go_next()) { set_opacity('next', global_default_opacity); } };

	var close = document.getElementById('close');
	close.onmousedown = function() { set_opacity('close', global_highlight_opacity); };
	close.onmouseup = function() { set_opacity('close', global_default_opacity); do_close(); };
	close.onmouseout = function() { set_opacity('close', global_default_opacity); };

	var options = document.getElementById('options');
	options.onmousedown = function() { set_opacity('options', global_highlight_opacity); };
	options.onmouseup = function() { set_opacity('options', global_default_opacity); toggle_optionmenu(); };
	options.onmouseout = function() { set_opacity('options', global_default_opacity); };
};

})();
