import java.io.FileNotFoundException; //<>// //<>//
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.List;

public static int debuglevel = 1; // between 0-2

// Used during The Shape of Things (2017-18)

// Usage:
// * set image filename and parameters
// * run
//   * SPACE to save
//   * press 'R' to restart with random settings
//   * press 'I' for interactive mode, mouse click or drag starts line (longer mouse movements take longer to calculate)
//   * click to view coordinates at that point
// NOTE: small changes to stroke_len, angles_no, stroke_alpha may have dramatic effect

// image filename
String filename = "Auditorium-Patio-Flat";
String fileext = ".png";
String foldername = "./";
String foldernameabs = "./Desktop/Tech-Image-Effects/processing/line_rendering/";
String foldernameabsnd = "/Desktop/Tech-Image-Effects/processing/line_rendering/";

int stat_type = ABSDIST2; // type of diff calculation: fast: ABSDIST, ABSDIST2, DIST, slow: HUE, SATURATION, BRIGHTNESS
int stroke_len = 9; // length of the stroke; 1 and above (default 5)
int angles_no = 43; // number of directions the stroke can be drawn; 2 and above (default 30)
int segments = 770; // number of segments in a single thread (default 500)
float stroke_width = 2.0613706; // width of the stroke; 0.5 - 3 (default 1)
int stroke_alpha = 124; // alpha channel of the stroke; 30 - 200 (default 100)

// Settings can be copied from the console and pasted in the space below. (Remember to comment out the settings above before running the script) 



color background_color = color(0, 0, 0); // RGB (default 255,255,255)

boolean interactive = false; // (default false)

PImage img;

// working buffer
PGraphics buffer;

String sessionid;

int n = 1;
int frame = 1;
String framedir;
String framedirabs;
String videodir;

int drawnum = 1;

void settings() {
  PImage oimg = loadImage(foldername+filename+fileext);
  int ow = oimg.width;
  int oh = oimg.height;
  if (ow % 2 != 0 ) {
    ow = ow - 1;
    if (debuglevel > 0) {
      println("Image width trimmed to " + ow);
    }
  }
  if (oh % 2 != 0 ) {
    oh = oh - 1;
    if (debuglevel > 0) {
      println("Image height trimmed to " + oh);
    }
  }
  img = oimg.get(0, 0, ow, oh); // Trim 1 pixel off any uneven dimension

  // calculate window size
  int max_display_size;
  if (img.width > img.height) {
    max_display_size = displayWidth;
  } else {
    max_display_size = displayHeight;
  }

  float ratio = (float)img.width/(float)img.height;
  int neww, newh;
  if (ratio < 1.0) {
    neww = (int)(max_display_size * ratio);
    newh = max_display_size;
  } else {
    neww = max_display_size;
    newh = (int)(max_display_size / ratio);
  }
  println("Canvas Display Dimensions: "+int(neww)+"x"+int(newh)); // The dimensions of the canvas as it is displayed in the output window
  println("");
  size(int(neww), int(newh)); // Set this equal to the dimensions of the image being rendered
}

void setup() {
  sessionid = hex((int)random(0xffff), 4);
  PImage oimg = loadImage(foldername+filename+fileext);
  int ow = oimg.width;
  int oh = oimg.height;
  if (ow % 2 != 0 ) {
    ow = ow - 1;
    if (debuglevel > 0) {
      println("Image width trimmed to " + ow);
    }
  }
  if (oh % 2 != 0 ) {
    oh = oh - 1;
    if (debuglevel > 0) {
      println("Image height trimmed to " + oh);
    }
  }
  img = oimg.get(0, 0, ow, oh); // Trim 1 pixel off any uneven dimension

  buffer = createGraphics(img.width, img.height);
  buffer.beginDraw();
  buffer.noFill();
  //buffer.smooth(8);
  buffer.endDraw();
  reinit();
  printParameters();
}

void reinit() {
  buffer.beginDraw();
  buffer.strokeWeight(stroke_width);
  buffer.background(background_color);
  buffer.endDraw();

  currx = (int)random(img.width);
  curry = (int)random(img.height); 

  if (debuglevel > 1) { 
    println("currx= " + currx);  
    println("curry= " + curry);
  }

  sintab = new int[angles_no];
  costab = new int[angles_no];

  for (int i=0; i<angles_no; i++) {
    sintab[i] = (int)(stroke_len * sin(TWO_PI*i/(float)angles_no));
    costab[i] = (int)(stroke_len * cos(TWO_PI*i/(float)angles_no));
  } 

  sqwidth = stroke_len * 2 + 4;
}

int currx, curry;
int[] sintab, costab;
int sqwidth;

int calcDiff(PImage img1, PImage img2) {
  int err = 0;
  for (int i=0; i<img1.pixels.length; i++)
    err += getStat(img1.pixels[i], img2.pixels[i]);
  return err;
}

void drawMe() {
  buffer.beginDraw();
  //draw whole segment using current color
  buffer.stroke(img.get(currx, curry), stroke_alpha);

  for (int iter=0; iter<segments; iter++) {
    // corners of square containing new strokes
    int corx = currx-stroke_len-2;
    int cory = curry-stroke_len-2;

    // take square from image and current screen
    PImage imgpart = img.get(corx, cory, sqwidth, sqwidth);
    PImage mypart = buffer.get(corx, cory, sqwidth, sqwidth);
    imgpart.loadPixels();
    mypart.loadPixels();

    // calc current diff 
    float localerr = calcDiff(imgpart, mypart);

    // chosen stroke will be here
    PImage destpart = null;
    int _nx=currx, _ny=curry;

    // start with random angle
    int i = (int)random(angles_no);
    int iterangles = angles_no;

    while (iterangles-- > 0) {
      // take end points
      int nx = currx + costab[i];
      int ny = curry + sintab[i];

      // if not out of the screen
      if (nx>=0 && nx<img.width-1 && ny>=0 && ny<img.height-1) {
        // clean region and draw line
        buffer.image(mypart, corx, cory);
        buffer.line(currx, curry, nx, ny);

        // take region with line and calc diff
        PImage curr = buffer.get(corx, cory, sqwidth, sqwidth);
        curr.loadPixels();
        int currerr = calcDiff(imgpart, curr);

        // if better, remember this region and line endpoint
        if (currerr < localerr) {
          destpart = curr;
          _nx = nx;
          _ny = ny;
          localerr = currerr;
          if (debuglevel > 1) {
            println("currerr= "+ currerr);
          }
        }
      }

      // next angle
      i = (i+1)%angles_no;
    }

    // if we have new stroke, draw it
    if (destpart != null) {
      buffer.image(destpart, corx, cory);
      currx = _nx;
      curry = _ny;
      if (debuglevel > 1) {
        println("############## drawing frame "+drawnum+" ##############");
        drawnum++;
      }
    } else {
      break; // skip
    }
  }

  buffer.endDraw();
  image(buffer, 0, 0, width, height);

  if (frame == 1) {
    if (!new File("./Desktop/Tech-Image-Effects/").exists()) { 
      if (debuglevel > 0) {
        println("Script folder is not on the desktop. Changing references to Downloads...");
      }
      foldernameabs = "./Downloads/Tech-Image-Effects/processing/line_rendering/";
      foldernameabsnd = "/Downloads/Tech-Image-Effects/processing/line_rendering/";
    }
    framedir = foldername + filename + "/" + filename + "_Rendered_Frames_" + sessionid + "/";
    framedirabs = foldernameabs + filename + "/" + filename + "_Rendered_Frames_" + sessionid + "/";
    videodir = foldernameabs + "Videos/"; 
    PrintWriter writer = null;
    try {
      File compiler = new File(framedirabs + "compile.sh");
      File f = new File(framedirabs);

      if (debuglevel > 0) {
        println("f = " + f);
        println("f created? " + f.mkdir());        
        println("f is a directory? " + f.isDirectory());
        println("Creating video compilation script " + compiler);
        if (compiler.createNewFile() || compiler.isFile()) {
          println(compiler + " is a file");
        } else {
          println(compiler + " is a directory");
        }
      }

      f.mkdir();
      compiler.createNewFile();
      writer = new PrintWriter(new FileWriter(compiler));
      writer.println("#!/bin/bash");
      writer.println("d=$(pwd)");
      writer.println("nd=$(dirname $d)");
      writer.println("cd $(dirname $nd)");
      writer.println("mkdir Videos");
      writer.println("ffmpeg -pattern_type sequence -r 40 -f image2 -i \"$d/" + filename + "_%06d.png\" -vcodec libx264 -pix_fmt yuv420p \"./Videos/" + filename + " " + sessionid + ".mp4\"");
    } 
    catch (IOException e) {
      System.err.println("IOException: " + e.getMessage());
    }
    finally {
      if (writer != null) { 
        if (debuglevel > 0) {
          println("Success!");
        }
        writer.close();
      } else { 
        System.err.println("Failed to create compiler script");
      }
    }
  }

  buffer.save(framedir + "/" + filename + "_" + String.format("%06d", frame) + ".png");
  frame++;
}

void draw() {
  if (!interactive) {
    currx = (int)random(img.width);
    curry = (int)random(img.height);
    drawMe();
  }
}

void mouseDragged() {
  if (interactive) {
    print("+");
    currx = (int)map(mouseX, 0, width, 0, img.width);
    curry = (int)map(mouseY, 0, height, 0, img.height);
    drawMe();
  }
}

void mouseClicked() {
  if (!interactive) {
    println("("+ (int)mouseX +", "+ (int)mouseY +") | frame " + frame);
  } else {
    mouseDragged();
  }
}

void printParameters() { // The output parameters can be easily copied and pasted into the beginning of this script
  String s_stat_type = "";
  switch(stat_type) {
  case DIST: 
    s_stat_type = "DIST"; 
    break;
  case ABSDIST: 
    s_stat_type = "ABSDIST"; 
    break;
  case ABSDIST2: 
    s_stat_type = "ABSDIST2"; 
    break;
  case HUE: 
    s_stat_type = "HUE"; 
    break;
  case SATURATION: 
    s_stat_type = "SATURATION"; 
    break;
  case BRIGHTNESS: 
    s_stat_type = "BRIGHTNESS"; 
    break;
  default: 
    break;
  }
  println("int stat_type= " + s_stat_type +";");
  println("int stroke_len= " + stroke_len +";");
  println("int angles_no= " + angles_no +";");
  println("int segments= " + segments +";");
  println("float stroke_width= " + stroke_width +";");
  println("int stroke_alpha= " + stroke_alpha +";");
  println("");
}

void keyPressed() {
  println("");
  String s_stat_type = "";
  switch(stat_type) {
  case DIST: 
    s_stat_type = "DIST"; 
    break;
  case ABSDIST: 
    s_stat_type = "ABSDIST"; 
    break;
  case ABSDIST2: 
    s_stat_type = "ABSDIST2"; 
    break;
  case HUE: 
    s_stat_type = "HUE"; 
    break;
  case SATURATION: 
    s_stat_type = "SATURATION"; 
    break;
  case BRIGHTNESS: 
    s_stat_type = "BRIGHTNESS"; 
    break;
  default: 
    break;
  }
  if (keyCode == 32) {
    buffer.save(foldername + filename + "/res_" + filename + "_" + sessionid + "_stat=" + s_stat_type + "_len=" + stroke_len + "_ang=" + angles_no + "_seg=" + segments + "_width=" + stroke_width + "_alpha=" + stroke_alpha + "_" + hex((int)random(0xffff), 4)+fileext);
    print("image saved");
  } else if (key == 'i') {
    interactive = !interactive;
    println("interactive mode: " + (interactive?"ON":"OFF"));
  } else if (key == 'r') {
    stat_type = random(1)<0.05?(int)random(1, 4):random(1)<0.3?ABSDIST:random(1)<0.5?ABSDIST2:DIST;
    stroke_len = (int)random(1, 15);
    angles_no = (int)random(2, 50);
    segments = (int)random(50, 1500);
    stroke_width = random(1)<0.7?1.0:random(0.5, 3);
    stroke_alpha = (int)random(50, 200);
    frame = 1;
    reinit();
    printParameters();
  }
}

final static int DIST = 0;
final static int HUE = 1;
final static int BRIGHTNESS = 2;
final static int SATURATION = 3;
final static int ABSDIST = 4;
final static int ABSDIST2 = 5;

final float getStat(color c1, color c2) {
  switch (stat_type) {
  case HUE: 
    abs(hue(c1)-hue(c2));
  case BRIGHTNESS: 
    abs(brightness(c1)-brightness(c2));
  case SATURATION: 
    abs(saturation(c1)-saturation(c2));
  case ABSDIST: 
    return abs(red(c1)-red(c2))+abs(green(c1)-green(c2))+abs(blue(c1)-blue(c2));
  case ABSDIST2: 
    return abs( (red(c1)+blue(c1)+green(c1)) - (red(c2)+blue(c2)+green(c2)) );
  default: 
    return sq(red(c1)-red(c2)) + sq(green(c1)-green(c2)) + sq(blue(c1)-blue(c2));
  }
}