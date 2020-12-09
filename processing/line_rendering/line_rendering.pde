import java.io.FileNotFoundException;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.List;
import java.util.LinkedList;
import java.util.Queue;
import java.util.concurrent.TimeUnit;
import java.awt.FlowLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import javax.swing.JFileChooser;

// Used during The Shape of Things (2017-18)

// Usage:
// * set image filename and parameters
// * run
//   * SPACE to save
//   * press 'R' to restart with random settings
//   * press 'I' for interactive mode, mouse click or drag starts line (longer mouse movements take longer to calculate)
//   * click to view coordinates at that point and the current frame
// NOTE: small changes to stroke_len, angles_no, stroke_alpha may have dramatic effect

public static int debuglevel = 1; // between 0-2

Boolean writeframes = true; // Determines whether rendered frames will be written to the disk
Boolean autorestart = true; // If true, the rendering will be restarted upon reaching the set maxframes
Boolean autorandom = true; // If true, randomizes the settings after an auto restart
Boolean randomstart = true; // If true, randomizes starting parameters, ignoring any set below
Boolean maxcanvas = false; // If false and the image is smaller than the display, the canvas will be the size of the image; otherwise it will be as large as possible within the display dimensions

int stat_type = ABSDIST2; // color diff calculation method: fast: ABSDIST, ABSDIST2, DIST, slow: HUE, SATURATION, BRIGHTNESS
int stroke_len = 12; // length of the stroke; 1 and above (default 5)
int angles_no = 39; // number of directions the stroke can be drawn; 2 and above (default 30)
int segments = 1029; // number of segments in a single thread (default 500)
float stroke_width = 1.0; // width of the stroke; 0.5 - 3 (default 1)
int stroke_alpha = 142; // alpha channel of the stroke; 30 - 200 (default 100)
int maxframes = 2000; // the number of frames to render before starting a new rendering (with the same settings)

// Settings can be copied from the console and pasted in the space below. (Remember to comment out the settings above before running the script) 



color background_color = color(0, 0, 0); // RGB (default 255,255,255)

boolean interactive = false; // (default false)

// working buffer
PGraphics buffer;

String filename;
String fileext;
Boolean filechosen=false;
PImage img;
PFont mono;
String sessionid;

int n = 1;
int frame = 1;
String pwd;
String framedir;
String videodir;
long frameStart, frameEnd, renderStart, renderEnd;
Queue<Double> renderTimes = new LinkedList<Double>();

int drawnum = 1;

void settings() {
  pwd = sketchPath() + "/";
  sessionid = hex((int) random(0xffff), 4); // Generate a unique id for this session for use in generated file names
  JFileChooser fc = new JFileChooser();
  File f = new File(pwd);
  fc.setCurrentDirectory(f); 
  // Show open dialog
  fc.showOpenDialog(null);
  File selFile = fc.getSelectedFile();
  if (selFile == null) {
    println("You need to select an image to render.");
    System.exit(1);
  } else {
    filename = selFile.getName().substring(0, selFile.getName().length() - (getExtension(selFile.getName()).length()+1)); // Sets filename without file extension
    fileext = getExtension(selFile.getName());
  }
  if (randomstart) {
    randomizeParameters();
  }
  // Load selected image and trim it to even dimensions
  PImage oimg = loadImage(pwd + filename + "."+ fileext);
  int ow = oimg.width;
  int oh = oimg.height;
  if (ow % 2 != 0) {
    ow = ow - 1;
    if (debuglevel > 0) {
      println("Image width trimmed to " + ow);
    }
  }
  if (oh % 2 != 0) {
    oh = oh - 1;
    if (debuglevel > 0) {
      println("Image height trimmed to " + oh);
    }
  }
  img = oimg.get(0, 0, ow, oh); // Trim 1 pixel off any uneven dimension (trims one pixel off the bottom and/or right side if necessary)
  // Calculate output window dimensions
  int max_window_size;
  if (maxcanvas) {
    max_window_size = displayWidth;
  } else {
    max_window_size = (oimg.width < displayWidth) ? oimg.width : displayWidth;
  }
  float ratio = (float) img.width / (float) img.height;
  int neww, newh;
  if (ratio < 1.0) {
    neww = (int)(max_window_size * ratio);
    newh = max_window_size;
  } else {
    neww = max_window_size;
    newh = (int)(max_window_size / ratio);
  }
  println("Canvas Display Dimensions: " + int(neww) + "x" + int(newh)); // The dimensions of the canvas as it is displayed in the output window
  println("");
  size(int(neww), int(newh)); // Set window size equal to the dimensions of the image being rendered
}

void setup() {
  mono = createFont("Consolas", 12);
  textFont(mono);
  buffer = createGraphics(img.width, img.height);
  buffer.beginDraw();
  buffer.noFill();
  //buffer.smooth(8);
  buffer.endDraw();
  reinit();
  printParameters();
}

void reinit() {
  renderStart = System.nanoTime();
  buffer.beginDraw();
  buffer.strokeWeight(stroke_width);
  buffer.background(background_color);
  buffer.endDraw();

  currx = (int) random(img.width);
  curry = (int) random(img.height);

  if (debuglevel > 1) {
    println("currx= " + currx);
    println("curry= " + curry);
  }

  sintab = new int[angles_no];
  costab = new int[angles_no];

  for (int i = 0; i < angles_no; i++) {
    sintab[i] = (int)(stroke_len * sin(TWO_PI * i / (float) angles_no));
    costab[i] = (int)(stroke_len * cos(TWO_PI * i / (float) angles_no));
  }

  sqwidth = stroke_len * 2 + 4;
}

int currx, curry;
int[] sintab, costab;
int sqwidth;

int calcDiff(PImage img1, PImage img2) {
  int err = 0;
  for (int i = 0; i < img1.pixels.length; i++)
    err += getStat(img1.pixels[i], img2.pixels[i]);
  return err;
}

void drawMe() {
  pwd = sketchPath() + "/";
  buffer.beginDraw();
  // draw whole segment using current color
  buffer.stroke(img.get(currx, curry), stroke_alpha);

  for (int iter = 0; iter < segments; iter++) {
    // corners of square containing new strokes
    int corx = currx - stroke_len - 2;
    int cory = curry - stroke_len - 2;

    // take square from image and current screen
    PImage imgpart = img.get(corx, cory, sqwidth, sqwidth);
    PImage mypart = buffer.get(corx, cory, sqwidth, sqwidth);
    imgpart.loadPixels();
    mypart.loadPixels();

    // calc current diff 
    float localerr = calcDiff(imgpart, mypart);

    // chosen stroke will be here
    PImage destpart = null;
    int _nx = currx, _ny = curry;

    // start with random angle
    int i = (int) random(angles_no);
    int iterangles = angles_no;
    // TODO: Consider adding an option to randomize the order of sintab[] and costab[] for every line. 

    while (iterangles--> 0) {
      // take end points
      int nx = currx + costab[i];
      int ny = curry + sintab[i];

      // if not out of the screen
      if (nx >= 0 && nx < img.width - 1 && ny >= 0 && ny < img.height - 1) {
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
            println("currerr= " + currerr);
          }
        }
      }

      // next angle
      i = (i + 1) % angles_no;
    }

    // if we have new stroke, draw it
    if (destpart != null) {
      buffer.image(destpart, corx, cory);
      currx = _nx;
      curry = _ny;
      if (debuglevel > 1) {
        println("############## drawing frame " + drawnum + " ##############");
        drawnum++;
      }
    } else {
      break; // skip
    }
  }

  buffer.endDraw();
  image(buffer, 0, 0, width, height);

  if (writeframes == true) {
    if (frame == 1) {
      framedir = pwd + "Rendered/" + filename + "/" + filename + "_Rendered_Frames_" + sessionid + "/";
      videodir = pwd + "Videos/";
      println();
      println("framedir = " + framedir);
      println("videodir = " + videodir);
      PrintWriter writer = null;
      try { // Creates a directory for rendered frame output and create a compiler script
        String cname = "compile.sh";
        OsCheck.OSType ostype = OsCheck.getOperatingSystemType();
        println("os = " + ostype);
        switch (ostype) {
        case Windows:
          {
            cname = "compile.bat";
            break;
          }
        case MacOS:
        case Linux:
          {
            cname = "compile.sh";
            break;
          }
        case Other:
          throw new IOException("Operating system could not be determined."); // Throws an exception if unable to determine the operating system
        }

        File compiler = new File(framedir + cname);
        File f = new File(framedir);

        if (debuglevel > 0) {
          println("f = " + f);
          println("f created? " + f.mkdirs());
          println("f is a directory? " + f.isDirectory());
          println("Creating video compilation script " + compiler);
          if (compiler.createNewFile() || compiler.isFile()) {
            println(compiler + " is a file");
          } else {
            println(compiler + " is a directory");
          }
        }

        f.mkdirs();
        compiler.createNewFile();
        writer = new PrintWriter(new FileWriter(compiler));
        switch (ostype) {
        case Windows:
          {
            writer.println("@echo off");
            writer.println("set d=%~dp0");
            writer.println("echo \"%d%\"");
            writer.println("for %%a in (\"%d%\") do set \"p_dir=%%~dpa\"");
            writer.println("for %%a in (%p_dir:~0,-1%) do set \"p2_dir=%%~dpa\"");
            writer.println("for %%a in (%p2_dir:~0,-1%) do set \"p3_dir=%%~dpa\"");
            writer.println("set videodir=%p3_dir%Videos");
            writer.println("echo %videodir%");
            writer.println("if not exist %videodir% mkdir %videodir%");
            writer.println("cd %videodir%");
            writer.println("ffmpeg -n -pattern_type sequence -r 40 -f image2 -i \"%d%\\" + filename + "_%%06d.png\" -vcodec libx264 -pix_fmt yuv420p \"%videodir%\\" + filename + " " + sessionid + ".mp4\"");
            writer.println("rem ffmpeg -n -pattern_type sequence -r 40 -f image2 -i \"%d%\\" + filename + "_%%06d.png\" -vcodec libx264 -pix_fmt yuv420p -vf reverse \"%videodir%\\" + filename + " " + sessionid + " Reverse.mp4\"");
            break;
          }
        case MacOS:
        case Linux:
          {
            writer.println("#!/bin/bash");
            writer.println("d=$(pwd)");
            writer.println("ud=$(dirname $d)");
            writer.println("nd=$(dirname $ud)");
            writer.println("cd $(dirname $nd)");
            writer.println("mkdir Videos");
            writer.println("ffmpeg -n -pattern_type sequence -r 40 -f image2 -i \"$d/" + filename + "_%06d.png\" -vcodec libx264 -pix_fmt yuv420p \"./Videos/" + filename + " " + sessionid + ".mp4\"");
            writer.println("# ffmpeg -n -pattern_type sequence -r 40 -f image2 -i \"$d/" + filename + "_%06d.png\" -vcodec libx264 -pix_fmt yuv420p -vf reverse \"./Videos/" + filename + " " + sessionid + " Reverse.mp4\"");
            break;
          }
        case Other:
          throw new IOException("Operating system could not be determined."); // Throws an exception if unable to determine the operating system
        }
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

      String sname = "settings.txt";
      File settingsfile = new File(framedir + sname);

      try {
        if (debuglevel > 0) {
          println("Saving settings to " + settingsfile);
          if (settingsfile.createNewFile() || settingsfile.isFile()) {
            println(settingsfile + " is a file");
          } else {
            println(settingsfile + " is a directory");
          }
        }
        settingsfile.createNewFile();
        writer = new PrintWriter(new FileWriter(settingsfile));
        writer.println("int stat_type= " + statType() + ";");
        writer.println("int stroke_len= " + stroke_len + ";");
        writer.println("int angles_no= " + angles_no + ";");
        writer.println("int segments= " + segments + ";");
        writer.println("float stroke_width= " + stroke_width + ";");
        writer.println("int stroke_alpha= " + stroke_alpha + ";");
        writer.println("int maxframes= " + maxframes + ";");
      } 
      catch (IOException e) {
        System.err.println("IOException: " + e.getMessage());
      } 
      finally {
        writer.close();
      }
    }
    buffer.save(framedir + "/" + filename + "_" + String.format("%06d", frame) + ".png");
  }

  frame++;
  if (frame > maxframes && autorestart) {
    println("");
    println("####################");
    println("Reached frame limit. Beginning new rendering...");
    println("");
    if (autorandom) {
      randomizeParameters();
    }
    frame = 1;
    sessionid = hex((int) random(0xffff), 4);
    reinit();
    printParameters();
  }
}

void draw() {
  if (!interactive) {
    frameStart = System.nanoTime();
    currx = (int) random(img.width);
    curry = (int) random(img.height);
    drawMe();
    frameEnd = System.nanoTime();
    drawOverlay();
  }
}

void drawOverlay() {
  // Write info about the current rendering in the top left of the window. This text is not saved to the buffer or rendered images.   
  double elapsedTime = (double)(frameEnd - frameStart) / 1000000; // Get the elapsed time in milliseconds
  renderTimes.add(elapsedTime);
  if (renderTimes.size() > 10) {
    renderTimes.remove();
  }
  double sum = 0;
  for (int i = 0; i < renderTimes.size(); i++) {
    double n = renderTimes.remove();
    sum += n;
    renderTimes.add(n);
  }
  double avg = sum / renderTimes.size();
  String[] textout = {
    "file:               " + filename, 
    "session id:         " + sessionid, 
    "frame:              " + frame, 
    "prev. render time:  " + (double)Math.round(elapsedTime*100d)/100d + " ms", 
    "avg render time:    " + (double)Math.round(avg*100d)/100d + " ms", 
    // "total render time : " + formatInterval(System.nanoTime()-renderStart),
    "autorestart:        " + autorestart, 
    "aurorandom:         " + autorandom, 
    "randomstart:        " + randomstart, 
    "maxframes:          " + maxframes, 
    "stat_type:          " + stat_type, 
    "stroke_len:         " + stroke_len, 
    "angles_no:          " + angles_no, 
    "segments:           " + segments, 
    "stroke_width:       " + stroke_width, 
    "stroke_alpha:       " + stroke_alpha, 
  };
  int lineheight = 16;
  for (int i=0; i<textout.length; i++) {
    text(textout[i], 5, lineheight*(i+1));
  }
}

private static String formatInterval(final long l) {
  final long hr = TimeUnit.MILLISECONDS.toHours(l);
  final long min = TimeUnit.MILLISECONDS.toMinutes(l - TimeUnit.HOURS.toMillis(hr));
  final long sec = TimeUnit.MILLISECONDS.toSeconds(l - TimeUnit.HOURS.toMillis(hr) - TimeUnit.MINUTES.toMillis(min));
  final long ms = TimeUnit.MILLISECONDS.toMillis(l - TimeUnit.HOURS.toMillis(hr) - TimeUnit.MINUTES.toMillis(min) - TimeUnit.SECONDS.toMillis(sec));
  return String.format("%02d:%02d:%02d.%03d", hr, min, sec, ms);
}

void mouseDragged() {
  if (interactive) {
    print("+");
    currx = (int) map(mouseX, 0, width, 0, img.width);
    curry = (int) map(mouseY, 0, height, 0, img.height);
    drawMe();
  }
}

void mouseClicked() {
  if (!interactive) {
    println("(" + (int) mouseX + ", " + (int) mouseY + ") | frame " + frame);
  } else {
    mouseDragged();
  }
}

String statType() {
  String s_stat_type = "";
  switch (stat_type) {
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
  return s_stat_type;
}

void randomizeParameters() {
  stat_type = random(1) < 0.05 ? (int) random(1, 4) : random(1) < 0.3 ? ABSDIST : random(1) < 0.5 ? ABSDIST2 : DIST;
  stroke_len = (int) random(1, 15);
  angles_no = (int) random(2, 50);
  segments = (int) random(50, 1500);
  stroke_width = random(1) < 0.7 ? 1.0 : random(0.5, 3);
  stroke_alpha = (int) random(50, 200);
}

void printParameters() { // Prints current rendering parameters in a format that can be easily copied into the beginning of this script
  println("int stat_type= " + statType() + ";");
  println("int stroke_len= " + stroke_len + ";");
  println("int angles_no= " + angles_no + ";");
  println("int segments= " + segments + ";");
  println("float stroke_width= " + stroke_width + ";");
  println("int stroke_alpha= " + stroke_alpha + ";");
  println("int maxframes= " + maxframes + ";");
  println("");
}

void keyPressed() {
  println("");
  if (keyCode == 32) { // Pressing SPACE saves a snapshot of the current frame to a folder in the project root directory with the current settings written in the filename
    buffer.save(pwd + "Snapshots/" + filename + "/res_" + filename + "_" + sessionid + "_stat=" + statType() + "_len=" + stroke_len + "_ang=" + angles_no + "_seg=" + segments + "_width=" + stroke_width + "_alpha=" + stroke_alpha + "_" + hex((int) random(0xffff), 4) + ".png");
    println("image saved | frame " + frame);
  } else if (key == 'i') { // Pressing I toggles interactive mode
    interactive = !interactive;
    println("interactive mode: " + (interactive ? "ON" : "OFF"));
  } else if (key == 'r') { // Pressing R restarts the rendering with random settings
    // autorestart = false; // Manually restarting the rendering disables automatic restarting of the rendering for the current session
    if (frame < 300) { // Manually restarting the rendering is only possible within the first 300 frames of generation
      stat_type = random(1) < 0.05 ? (int) random(1, 4) : random(1) < 0.3 ? ABSDIST : random(1) < 0.5 ? ABSDIST2 : DIST;
      stroke_len = (int) random(1, 15);
      angles_no = (int) random(2, 50);
      segments = (int) random(50, 1500);
      stroke_width = random(1) < 0.7 ? 1.0 : random(0.5, 3);
      stroke_alpha = (int) random(50, 200);
      frame = 1;
      println("");
      println("####################");
      println("Rendering manually restarted. Beginning new rendering...");
      println("");
      reinit();
      printParameters();
    } else {
      System.err.println("Please restart the script to create a new rendering");
    }
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
    abs(hue(c1) - hue(c2));
  case BRIGHTNESS:
    abs(brightness(c1) - brightness(c2));
  case SATURATION:
    abs(saturation(c1) - saturation(c2));
  case ABSDIST:
    return abs(red(c1) - red(c2)) + abs(green(c1) - green(c2)) + abs(blue(c1) - blue(c2));
  case ABSDIST2:
    return abs((red(c1) + blue(c1) + green(c1)) - (red(c2) + blue(c2) + green(c2)));
  default:
    return sq(red(c1) - red(c2)) + sq(green(c1) - green(c2)) + sq(blue(c1) - blue(c2));
  }
}

/**
 * helper class to check the operating system this Java VM runs in
 *
 * please keep the notes below as a pseudo-license
 *
 * http://stackoverflow.com/questions/228477/how-do-i-programmatically-determine-operating-system-in-java
 * compare to http://svn.terracotta.org/svn/tc/dso/tags/2.6.4/code/base/common/src/com/tc/util/runtime/Os.java
 * http://www.docjar.com/html/api/org/apache/commons/lang/SystemUtils.java.html
 */
import java.util.Locale;
public static final class OsCheck {
  /**
   * types of Operating Systems
   */
  public enum OSType {
    Windows, 
      MacOS, 
      Linux, 
      Other
  };

  // cached result of OS detection
  protected static OSType detectedOS;

  /**
   * detect the operating system from the os.name System property and cache
   * the result
   * 
   * @returns - the operating system detected
   */
  public static OSType getOperatingSystemType() {
    if (detectedOS == null) {
      String OS = System.getProperty("os.name", "generic").toLowerCase(Locale.ENGLISH);
      if ((OS.indexOf("mac") >= 0) || (OS.indexOf("darwin") >= 0)) {
        detectedOS = OSType.MacOS;
      } else if (OS.indexOf("win") >= 0) {
        detectedOS = OSType.Windows;
      } else if (OS.indexOf("nux") >= 0) {
        detectedOS = OSType.Linux;
      } else {
        detectedOS = OSType.Other;
      }
    }
    return detectedOS;
  }
}

public static String getExtension(String fileName) {
    char ch;
    int len;
    if(fileName==null || 
            (len = fileName.length())==0 || 
            (ch = fileName.charAt(len-1))=='/' || ch=='\\' || //in the case of a directory
             ch=='.' ) //in the case of . or ..
        return "";
    int dotInd = fileName.lastIndexOf('.'),
        sepInd = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
    if( dotInd<=sepInd )
        return "";
    else
        return fileName.substring(dotInd+1).toLowerCase();
}
