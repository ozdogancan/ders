/**
 * Framer Motion animation presets for Koala.
 * Usage:  <motion.div {...fadeIn}>  or  <motion.div variants={stagger.container} initial="hidden" animate="show">
 */
import type { Variants } from 'framer-motion';

/* -------------------------------------------------- */
/*  Transition curves                                  */
/* -------------------------------------------------- */
const spring = { type: 'spring' as const, stiffness: 300, damping: 24 };
const ease = { duration: 0.35, ease: [0.25, 0.1, 0.25, 1] as const };

/* -------------------------------------------------- */
/*  Simple presets (spread directly onto motion.*)     */
/* -------------------------------------------------- */
export const fadeIn = {
  initial: { opacity: 0 },
  animate: { opacity: 1 },
  transition: ease,
};

export const fadeInUp = {
  initial: { opacity: 0, y: 20 },
  animate: { opacity: 1, y: 0 },
  transition: ease,
};

export const fadeInDown = {
  initial: { opacity: 0, y: -20 },
  animate: { opacity: 1, y: 0 },
  transition: ease,
};

export const scaleIn = {
  initial: { opacity: 0, scale: 0.95 },
  animate: { opacity: 1, scale: 1 },
  transition: spring,
};

export const slideInLeft = {
  initial: { opacity: 0, x: -30 },
  animate: { opacity: 1, x: 0 },
  transition: ease,
};

export const slideInRight = {
  initial: { opacity: 0, x: 30 },
  animate: { opacity: 1, x: 0 },
  transition: ease,
};

/* -------------------------------------------------- */
/*  Stagger children (container + item variants)       */
/* -------------------------------------------------- */
export const stagger = {
  container: {
    hidden: {},
    show: {
      transition: { staggerChildren: 0.08 },
    },
  } satisfies Variants,

  item: {
    hidden: { opacity: 0, y: 16 },
    show: { opacity: 1, y: 0, transition: ease },
  } satisfies Variants,
};

/* -------------------------------------------------- */
/*  Page transition (for layout animations)            */
/* -------------------------------------------------- */
export const pageTransition = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -8 },
  transition: { duration: 0.25 },
};

/* -------------------------------------------------- */
/*  Hover / tap micro-interactions                     */
/* -------------------------------------------------- */
export const tap = { scale: 0.97 };
export const hover = { scale: 1.02 };
export const hoverLift = { y: -4, boxShadow: '0 8px 24px rgba(0,0,0,0.08)' };
