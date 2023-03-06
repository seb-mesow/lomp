# Karatsuba Square Root Algorithm

We implement the recursive Karatsuba Square Root Algorithm by Paul Zimmermann
as described in the following two papers:

1. https://hal.inria.fr/inria-00072854/document
2. https://hal.inria.fr/inria-00072113/document

**Table Of Contents**

1. [Variables](#variables)
    1. [Arbitrary-Precision Environment](#arbitrary-precision-environment)
    2. [Normalizing the Input $X\_u$](#normalizing-the-input-x_u)
        1. [Minimization Precondition](#minimization-precondition)
    3. [Splitting the Normalized Input $X$](#splitting-the-normalized-input-x)
        1. [Normalization Precondition](#normalization-precondition)
    4. [Recursive Call of $SqrtRem\_Impl()$](#recursive-call-of-sqrtrem_impl)
    5. [Division with $DivRem()$](#division-with-divrem)
    6. [Computing the Preliminary Return Values](#computing-the-preliminary-return-values)
    7. [Computing the Final Return Values](#computing-the-final-return-values)
2. [Wrapper Function $SqrtRem\_Wrap()$](#wrapper-function-sqrtrem_wrap)
    1. [1st-level Pseudo Code](#1st-level-pseudo-code)
    2. [3rd-level Pseudo Code](#3rd-level-pseudo-code)
3. [Implementation Function](#implementation-function)
    1. [1st-level Pseudo Code](#1st-level-pseudo-code-1)
    2. [2nd-level Pseudo Code](#2nd-level-pseudo-code)
    3. [3rd-level Pseudo Code](#3rd-level-pseudo-code-1)


## Variables

### Arbitrary-Precision Environment

| Symbol | Explanation | Notes |
| :---:  | :---        | :---  |
| $b$    | `WIDTH`     | must be even |
| $B$    | `RADIX`     | $B = 2^b$ |

### Normalizing the Input $X_u$

| Symbol | Explanation        | Notes |
| :---:  | :---               | :---  |
| $X_u$ | unnormalized input | length $m_u$<br>$X_u < M_u$ |
| $m_u$ | length of the unnormalized input $X_u$ ||
| $M_u$ | radix corresponding to $m_u$ | $M_u = B^{m_u}$ |

#### Minimization Precondition

$$ B^{m_u} \stackrel{!}{>} X_u \stackrel{!}{\ge} B^{m_u-1} \iff B > X_u[m_u-1] \stackrel{!}{\ge} 1$$

Thus $X$ must not have any leading zero limbs resp. in the most significant limb at least one bit must be set.

### Splitting the Normalized Input $X$

| Symbol | Explanation        | Notes |
| :---:  | :---               | :---  |
| $m$ | length of normalized input      | must be even |
| $n$ | half length of normalized input | |
| $l$ | length of the lower two quarters of the normalized input $N_1$ and $N_0$ ||
| $h$ | "half" length of the higher half of input $N_{23}$ | |

| $n$ is |    even            |        odd          |
| :---:  | :---:              | :---:               |
| (1)    | $l = \frac{n}{2}$  | $l = \frac{n-1}{2}$ |
| (2)    | $2l = n$           | $2l + 1 = n$        |
| (3)    | $h = \frac{n}{2}$  | $h = \frac{n+1}{2}$ |
| (4)    | $2h = n$           | $2h - 1 = n$        |
| (5)    | $h + l = n$        | $h + l = n$         |
| (6)    | $2h + 2l = 2n = m$ | $2h + 2l = 2n = m$  |

| Symbol | Explanation        | Notes |
| :---:  | :---               | :---  |
| $M$ | radix corresponding to $m$ | $M = B^m = 2^{mb}$ |
| $N$ | radix corresponding to $n$ | $N = B^n = 2^{nb}$ |
| $L$ | radix corresponding to $l$ | $L = B^l = 2^{lb}$ |
| $H$ | radix corresponding to $h$ | $H = B^h = 2^{hb}$ |

$$\begin{align*}
HL     &= N &= B^n &= 2^{(h+l)b} \\
H^2L^2 &= M &= B^m &= 2^{(2h+2l)b}
\end{align*}$$

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $X$      | normalized input       | length $m$<br>$X < M$ | 
| $X_{23}$ | higher "half" of input | length $2h$<br>$X_{23} < H^2$ |
| $X_1$    | 2nd "quarter" of input | length $l$<br>$X_1 < L$ |
| $X_0$    | 1st "quarter" of input | length $l$<br>$X_0 < L$ |

$$ X = X_{23}L^2 + X_1L + X_0 $$

#### Normalization Precondition

$$ B^{2n} \stackrel{!}{>} X_u \stackrel{!}{\ge} \frac{B^{2n}}{4} \iff 2^{2nb} > X_u[m_u-1] \stackrel{!}{\ge} 2^{2nb-2}$$

Thus $X_u$ must fulfil the minimization and the most and/or second most significant bit must be set.

### Recursive Call of $SqrtRem\_Impl()$

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $S_p$    | partial square root                                            | length $h$<br>        $S_p < H$       |
| $R_{po}$ | partial square root remainder without its overflow bit $r_p$   | length $h$<br>$R_{po} < H$            |
| $R_p$    | partial square root remainder with    its overflow bit $r_p$   | $R_p = r_pH + R_{po}$<br> $R_p \le H$ |
| $r_p$    | partial square root remainder overflow bit                     | $r_p = 0 \text{ or } 1$               |

### Division with $DivRem()$

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $Q_{to}$ | preliminary quotient without its overflow bit $q_t$ | length $l = n-l$<br>  $Q_{to} < L$       |
| $Q_t$    | preliminary quotient with    its overflow bit $q_t$ | $Q_t = q_tL + Q_{to}$<br> $Q_t \le L$    |
| $q_t$    | preliminary quotient overflow bit                   | $q_t = 0\text{ or }1$                    |

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $U_t$    | preliminary division remainder                      | length $l$<br>   $U_t < L$               |

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $Q_o$ | quotient without its overflow bit $q$       | length $l$<br>        $Q_o < L$             |
| $Q$   | quotient with    its overflow bit $q$       | $Q = qL + Q_o$<br> $Q \le L$                |
| $q$   | quotient overflow bit                       | $q = 0\text{ or }1$                         |

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $U_o$ | division remainder without its overflow bit | length $h$<br>$U_o < H$                     |
| $U$   | division remainder with    its overflow bit | length $h$<br>$U = uH + U_o$<br>$U \le H$   |
| $u$   | division remainder overflow bit             | $u = 0\text{ or }1$                         |

### Computing the Preliminary Return Values

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $S_{to}$ | preliminary square root without its overflow bit $s_t$ | length $n$<br> $S_{to} < N$ |
| $S_t$    | preliminary square root with    its overflow bit $s_t$ | $S_t = s_t N + S_{to}$<br>$S_t \le N$ |
| $S_t$    | preliminary square root overflow bit | $s_t = 0\text{ or }1$ |

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $R_{to}$ | preliminary square root remainder without its overflow bit $r_t$ | length $n$<br> $R_{to} < N$ |
| $R_t$    | preliminary square root remainder with    its overflow bit $r_t$ | $R_t = r_t N + R_{to}$<br>$R_t \le N$ |
| $r_t$    | preliminary square root remainder overflow bit | $r_t = 0\text{ or }1$ |

### Computing the Final Return Values

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $S_o$ | square root without its temporary overflow bit $s$ | length $n$<br>$S < N$ |
| $S$   | square root with    its temporary overflow bit $s$ | $S = sN + S_o$<br>temporary: $S \le N$<br>finally: $S < N$ |
| $s$   | square root temporary overflow bit | temporary: $s = 0\text{ or }1$<br>finally: $s = 0$ |

| Symbol   | Explanation          | Notes |
| :---:    | :---                 | :---  |
| $R_o$ | square root remainder without its overflow bit $r$ | length $n$<br>$R_o < N$ |
| $R$   | square root remainder with    its overflow bit $r$ | $R = rN + R_o$<br>$R \le N$
| $r$   | square root remainder overflow bit | $r = 0\text{ or }1$ |


## Wrapper Function $SqrtRem\_Wrap()$

All <span style="color:orange">orange text</span> are actual statements to execute.<br>
All normal-colored text are comments

### 1st-level Pseudo Code

**Algorithm $SqrtRem\_Wrap()$**

Input: 

### 3rd-level Pseudo Code

Syntax: $S, r, R_o := mpn\_SqrtRem\_Wrap(X, m)$

Input:
- input number $X$
- its length $m_u$

Preconditions:
1. $m_u$ is the minimal length of $X$
    - 1\. $X \ge B^{m_u-1}$
    - 2\. $X < B^{m_u}$

Output:
- square root $S$
    - will have length $$
- square root remainder without its overflow bit $R_o$
    - TODO length
- square root remainder overflow bit $r$

Postconditions:
- with $m_h =\lceil\frac{m_u}{2}\rceil$
1. integer square root condition:
    - 1\. $S^2 \le X$
    - 2\. $(S+1)^2 > X$
2. remainder condition: $S^2 + rB^{m_h} + R_o = X$
3. $S$ has length $m_h$
    - 1\. $S \ge 0$ 
    - 2\. $S < B^{m_h}$ 
4. $R_o$ has length $m_h$
    - 1\. $R_o \ge 0$ 
    - 2\. $R_o < B^{m_h}$ 

## Implementation Function

All <span style="color:orange">orange text</span> are actual statements to execute.<br>
All normal-colored text are comments

### 1st-level Pseudo Code

Syntax: $S, R := SqrtRem\_Impl(X)$

Input:
- normalized input number $X$

Preconditions:
- 1\. Normalization Condition
    - with $m$ the minimal length of $X$
    - 1\. $X \ge \frac{B^m}{4}$
    - 2\. $X < B^m$

Output:
- square root $S$
- square root remaninder $R$

Postconditions:
- 1\. Integer Square Root Condition:
    - 1\. $S^2 \le X$
    - 2\. $(S+1)^2 > X$
- 2\. Integer Square Root Remainder Condition: $S^2 + R = X$

Algorithm:
- <span style="color:orange">1. compute $H,L$ such that</span>
    - <span style="color:orange">$HL = N$
    - <span style="color:orange">$H \ge L$
    - <span style="color:orange">$X = X_{23}L^2 + X_1L+ X_0$</span>
- <span style="color:orange">2. $S_p, R_p := SqrtRem\_Wrap(X_{23})$</span>
- <span style="color:orange">3. $Q, U := DivRem(R_p L+X_1, 2S_p)$</span>
- <span style="color:orange">4. $R_t := U L + X_0 - Q^2$</span>
- <span style="color:orange">5. $S_t := S L + Q$</span>
- <span style="color:orange">6.</span> correct return values:
    - <span style="color:orange">1. if $R_t < 0$ then</span>
        - <span style="color:orange">1. $R := R_t + 2S_t - 1$</span>
        - <span style="color:orange">2. $S := S_t - 1$</span>
    - <span style="color:orange">2. else</span>
        - if $R_t \ge 0$
        - <span style="color:orange">1. $R := R_t$</span>
        - <span style="color:orange">2. $S := S_t$</span>


### 2nd-level Pseudo Code

Syntax: $S, R := SqrtRem\_Impl(X)$

Input:
- normalized input number $X$

Preconditions:
- 1\. Normalization Condition
    - with $m$ the minimal length of $X$
    - 1\. $X \ge \frac{B^m}{4}$
    - 2\. $X < B^m$

Output:
- square root $S$
- square root remaninder $R$

Postconditions:
- 1\. Integer Square Root Condition:
    - 1\. $S^2 \le X$
    - 2\. $(S+1)^2 > X$
- 2\. Integer Square Root Remainder Condition: $S^2 + R = X$

Algorithm:
- <span style="color:orange">1. compute $H,L$ such that</span>
    - <span style="color:orange">$HL = N$</span>
    - <span style="color:orange">$H \ge L$</span>
    - <span style="color:orange">$X = X_{23}L^2 + X_1L+ X_0$</span>
- <span style="color:orange">2. $S_p, R_p := SqrtRem\_Wrap(X_{23})$</span>
- <span style="color:orange">3.</span> $Q, U := DivRem(R_p L+X_1, 2S_p)$
    - it holds $Q\cdot 2S_p + U = R_pL + X_1$
    - it holds $Q < L$ (see research paper)
    - it holds $U < 2S_p$
    - <span style="color:orange">1. $Q_t, U_t := DivRem(R_p L + X_1, S_p)$</span>
    - it holds $Q_tS_p + U_t = R_pL+X_1$
    - it must hold $Q\cdot 2S_p + U \stackrel{!}{=} R_p L + X_1$
    - <span style="color:orange">2. $Q := \lfloor\frac{Q_t}{2}\rfloor$</span>
    - if $Q_t$ is even:
        - it holds $2Q = Q_t$
        - it holds<br>
          $\quad Q_tS_p + U_t = R_pL + X_1$<br>
          $= 2Q\cdot S_p + U_t$<br>
          $= Q\cdot 2S_p + U$<br>
          with $U := U_t$<br>
    - if $Q_t$ is odd:
        - it holds $2Q + 1 = Q_t$
        - it holds<br>
          $\quad Q_tS_p + U_t = R_pL + X_1$<br>
          $= (2Q+1)S_p + U_t$<br>
          $= 2Q\cdot S_p + S_p + U_t$<br>
          $= Q\cdot 2S_p + U$<br>
          with $U := U_t + S_p$
    - <span style="color:orange">3.</span> correct division remainder:
        - <span style="color:orange">1. if $Q_t$ is odd then</span>
            - <span style="color:orange">1. $U := U_t + S_p$</span>
        - <span style="color:orange">2. else</span>
            - if $Q_t$ is even
            - <span style="color:orange">1. $U := U_t$</span>
- <span style="color:orange">4.</span> $R_t := U L + X_0 - Q^2$
    - <span style="color:orange">1. $Q_{sqr} := Q^2$</span>
    - <span style="color:orange">2. $R := (UL + X_0) - Q_{sqr}$</span>
- <span style="color:orange">5.</span> $S_t := S L + Q$
    - <span style="color:orange">1. $S_t := S_p L + Q$</span>
    - it holds $S < N$ with $N = HL$
- <span style="color:orange">6.</span> correct return values:
    - <span style="color:orange">1. if $R_t < 0$ then</span>
        - <span style="color:orange">1.</span> $R := R_t + 2S_t - 1$
            - <span style="color:orange">1. $R_{tt} := R_t + 2S_t$</span>
            - <span style="color:orange">2. $R := R_{tt} - 1$</span>
        - <span style="color:orange">2.</span> $S := S_t - 1$
            - <span style="color:orange">1. $S := S_t - 1$</span>
    - <span style="color:orange">2. else</span>
        - if $R_t \ge 0$
        - <span style="color:orange">1. $R := R_t$</span>
        - <span style="color:orange">2. $S := S_t$</span>

### 3rd-level Pseudo Code

Syntax: $S, rB^n+R_o := mpn\_SqrtRem\_Impl(X, n)$

Input:
- normalized input number $X$
- the exact half of its minimal length $n$
    - Thus the minimal length of $X$ must be even.

Preconditions:
- 1\. Normalization Condition
    - with $2n$ the minimal length of $X$
    - 1\. $X \ge \frac{B^{2n}}{4}$
    - 2\. $X < B^{2n}$

Output:
- square root $S$
    - will have length $n$
- square root remainder without its overflow bit $R_o$
    - will have length $n$
- square root remainder overflow bit $r$

Postconditions:
- 1\. Integer Square Root Condition:
    - 1\. $S^2 \le X$
    - 2\. $(S+1)^2 > X$
- 2\. Integer Square Root Remainder Condition: $S^2 + rB^n + R_o = X$
- 3\. $S$ has length $n$:
    - 1\. $S \ge 0$
    - 2\. $S < B^n$
- 3\. $R_o$ has length $n$:
    - 1\. $R_o \ge 0$
    - 2\. $R_o < B^n$

Algorithm:
- <span style="color:orange">1.</span> compute $H,L$ such that
    - $HL = N$
    - $H \ge L$
    - $X = X_{23}L^2 + X_1L+ X_0$
    - <span style="color:orange">1. $l := \lfloor\frac{n}{2}\rfloor$</span>
    - <span style="color:orange">2. $h := n - l$</span>
    - it holds $X_0 = X\mod B^l$
    - it holds $X_1 = (X/B^l)\mod B^l$
    - it holds $X_{23} = X/B^{2l}$
    - $X_0$ has length $l$
    - $X_1$ has length $l$
    - $X_{23}$ has the minimal length $2h$
- <span style="color:orange">2.</span> $S_p, R_p := SqrtRem\_Wrap(X_{23})$
    - $X_{23}$ is normalized:
        - Its most significant limb is equal to that of $X$.
        - Its minimal length $2h$ is even.
    - <span style="color:orange">1. $S_p, r_pH+R_{po} := mpn\_SqrtRem\_Impl(X_{23}, h)$</span>
    - $S_p$ has length $h$ resp. $S_p < H$
    - $R_{po}$ has length $h$ resp. $R_{po} < H$
    - $R_p = r_pH + R_{po}$
- <span style="color:orange">3.</span> $Q, U := DivRem(R_p L+X_1, 2S_p)$
    - <span style="color:orange">1.</span> $Q_t, U_t := DivRem(R_p L + X_1, S_p)$
        - We do not have $R_p$ at hand.
        - Also $R_p$ can be $H$ and thus may have a minimal length of $h+1$,
          which would make things a bit more complicate. 
        - We only have at hand $r_p$ and $R_{po} < N$ seperated.
        - Thus we like do something like $DivRem(R_{po}L + X_1, S_p)$ .
        - Suppose, we neglect the next subtraction:
            - If $r_p = 1 \iff R_p \ge H$,<br>
              then $R_{po} = R_p - H$<br>
              and  $Q_t, U_t := DivRem\big(R_{po}L + X_1, S_p\big)$<br>
              $= DivRem\big((R_p - H)L + X_1, S_p\big)$<br>
              $\iff Q_t S_p + U_t$<br>
              $= (R_p - H)L + X_1$<br>
              $= R_p L - HL + X_1$<br>
              $= R_p L + X_1 - N$<br>
              which is not desired.
        - How can we manipulate the dividend $R_{po}L + X_1$, such that<br>
          $\text{manageable side effect} + Q_t S_p + U_t = \text{manipulated}$ ?
        - Observe:
            - If we subtract $S_pL$ from the dividend, then the quotient is smaller by $L$ (manageable side effect).
        - Observe:
            - Because $R_p \le 2S_p = S_p + S_p$ and $S_p < H$,<br>
              is $R_p < S_p + H$<br>
              $\iff R_p - H < S_p$<br>
              $\iff R_p - H - S_p = R_{po} - S_p < 0$ .
            - With underflow ($+H$) $R_{po} - S_p$ is in reality<br>
              $R_p - H - S_p + H = R_p - S_p$ .
        - Conclusion:
            - If $R_p \ge H\iff r_p = 1$, then we replace $R_{po}$ by $R_{po} - S_p$
              and the *obtained* quotient $q_tL+Q_{to}$ is smaller than the *required* quotient $Q_t$ by $L$.
            - The $+H$ by the underflow propagates a borrow bit to the left
              and – as a nice side effect – mathematical precisely cancels $r_p$.
        - Check of this Idea:
            - $q_{t,ob}L+Q_{to}, U_t := DivRem\big((R_p - S_p)L + X_1, S_p\big)$<br>
              $\iff (q_{t,ob}L+Q_{to})S_p + U_t$<br>
              $= (R_p - S_p)L + X_1$<br>
              $= R_pL - S_pL + X_1$<br>
              $\iff (q_{t,ob}L+Q_{to})S_p + S_pL+ U_t = R_pL + X_1$<br>
              $= \big((q_{t,ob}+1)L+Q_{to}\big)S_p + U_t = R_pL + X_1$<br>
              $\iff (q_{t,ob}+1)L+Q_{to}, U_t = DivRem(R_pL + X_1, S_p)$<br>
              $=: q_tL+Q_{to}, U_t$
        - <span style="color:orange">1. if $r_p > 0$ then</span>
            - <span style="color:orange">1. $R_{po} := R_{po} - S_p$</span>
            - actually we would must also $r_p := 0$
        - $R_{po}L + X_1$ has length $h + l = n$
        - <span style="color:orange">2. $q_{t,ob}L+Q_{to}, U_t := mpn\_DivRem( R_{po}L + X_1, S_p)$</span>
        - $Q_{to} < L$, because $Q_{to}$ has length $l = n - h = (h + l) - h$<br>
          according to the postconditions of $mpn\_DivRem()$ . 
        - $U_t < S_p \implies U_t < H$, because $U_t$ has length $h$ (same as the divisior $S_p$)
        - if $r_p > 0 \iff r_p = 1 \iff R_p \ge H$, then the *required* $q_t$ is bigger than the *obtained* $q_{t,ob}$ by $1$ .
        - To reflect this in reality we, just add $r_p = 1$ to $q_{t,ob}$
          with the following addition.
        - If $r_p = 0 \iff R_p = R_{po}$, then the addition is useless.
        - <span style="color:orange">3. $q_t := q_{t,ob} + r_p$</span>
    - Now memorize: $Q_t = q_tL + Q_{to}$
    - it holds $Q_tS_p + U_t = R_pL + X_1$<br>
      $\iff (q_tL + Q_{to})S_p + U_t = (r_pH + R_{po})L + X_1$ .
    - <span style="color:orange">2.</span> $Q := \lfloor\frac{Q_t}{2}\rfloor$
        - <span style="color:orange">1. $Q_o := Q_{to}\ \texttt{>>}\ 1$</span>
           - $Q_o$ has length $l$, because $Q_{to}$ has length $l$ .
        - <span style="color:orange">2. $Q_o[l-1] := \big((q_t\ \texttt{\&}\ 1)\ \texttt{<<}\ (b-1)\big)\ \texttt{|}\ Q_o[l-1]$</span>
           - The least significant bit of $q_t$ as it shifts right floats
             into the most significant bit of the last limb of $Q_o$.
           - Because $Q_o$ has length $l$, the last limb is at index $l-1$. (zero-based index)
        - <span style="color:orange">3. $q := q_t\ \texttt{>>}\ 1$</span>
            - memorize: $q = 0\text{ or }1$ .
    - Now memorize: $Q = qL + Q_o$
    - <span style="color:orange">3.</span> correct division remainder:
        - 1\. if $Q_t$ is odd then
        - <span style="color:orange">1. if $Q_{to}\ \texttt{\&}\ 1 = 1$</span>
            - 1\. $U := U_t + S_p$
            - <span style="color:orange">1. $uH+U_o := U_t + S_p$</span>
        - <span style="color:orange">2.</span> else
            - if $Q_t$ is even
            - if $Q_{to}\ \texttt{\&}\ 1 = 0$
            - <span style="color:orange">1.</span> $U := U_t$
                - <span style="color:orange">1. $U_o := U_t$</span>
                - <span style="color:orange">2. $u := 0$</span>
    - $U_o$ has length $h$ resp. $U_o < H$ 
- <span style="color:orange">4.</span> $R_t := U L + X_0 - Q^2$
    - <span style="color:orange">1.</span> $Q_{sqr} := Q^2$
        - Recap $Q \le L$ (see research paper)
        - Thus either $q = 0$ or $Q_o = 0$ or both $= 0$,
          but never together $> 0$.
        - Thus always $qQ_o = 0$ .
        - $Q^2 = (qL+Q_o)^2$<br>
          $= qL^2 + 2qlQ_o + Q_o^2$<br>
          $= qL^2            + Q_o^2$<br>
          $=: qL^2 + Q_{o,sqr}$<br>
        - See how $q$ remains the same in $Q^2$ .
        - <span style="color:orange">1. $Q_{o,sqr} := Q_o^2$</span>
        - $Q_{o,sqr}$ has length $2l$, because $Q_o$ has length $l$ .
            - $Q_o < L \iff Q_o^2 < L^2$ 
        - Memorize: $Q_{sqr} = qL^2 + Q_{o,sqr}$
    - <span style="color:orange">2.</span> $R_t := (UL + X_0) - Q_{sqr}$
        - $U_oL + X_0$ has length $n = h + l$ .
        - $R_t = r_tN + R_{to}$<br>
          $:= (uH + U_o)L + X_0 - qL^2 - Q_{o,sqr}$<br>
          $= uHL - qL^2 +  U_oL + X_0    - Q_{o,sqr}$<br>
          $= uN  - qL^2 + (U_oL + X_0)   - Q_{o,sqr}$
        - <span style="color:orange">1. $main\_borrow\cdot B^{2l} + R_{to} := mpn\_sub\_n( U_oL + X_0, Q_{o,sqr}, 2l)$</span>
            - $mpn\_sub\_n(X,Y,n)$ subtracts the $n$ least significant limbs of $X$ and $Y$.
            - It leaves other limbs untouched. Thus a borrow is still returned.
        - If $h = l \iff n\ \text{is even}$, then $U_oL+X_1$ and $Q_{o,sqr}$ have the same length:
            - $U_oL + X_0$ has length $h + l = n$ .
            - $Q_{o,sqr}$ has  length $2l = n$ .
        - Then the difference $R_{to}$ has no limb to store the $main\_borrow$.
        - But if $h \ne l \iff h = l + 1 \iff n\ \text{is odd}$ ,<br>
          then $U_oL + X_1$ has one limb more than $Q_{o,sqr}$ :
            - $U_oL + X_1$ has length $h + l = n = 2l + 1$ .
            - $Q_{o,sqr}$ has length $2l$ .
                - Therefore not $n$ but $2l$ is provided to $mpn\_sub\_n()$ .
        - Thus the $main\_borrow$ must borrow from the last limb of the difference $R_{to}$.
        - <span style="color:orange">2.</span> assign borrows to their correct place
            - <span style="color:orange">1. if $h = l$ then</span>
                - $\iff$ if $n$ is even
                - $r$ is has the meaning of a carry, but can be negative.
                - $R_{to}$ has a length of $n = h + l = l + l = 2l$ .
                - Thus $-qL^2$ is shifted left out of $R_{to}$ as a borrow.
                - <span style="color:orange">1. $r_t := u - main\_borrow - q$</span>
            - <span style="color:orange">2. else</span>
                - else $l + 1 = h \iff n\ \text{is odd}$ 
                - and $2l + 1 = n$ .
                - $R_{to}$ has a length of $n = h + l = l + 1 + l = 2l + 1$ .
                - Thus $-qL^2$ goes into the last limb of $R_{to}$ .
                - The last limb of $R_{to}$ is at index $2l$. (zero-based index)
                - <span style="color:orange">1. $temp\_borrow\cdot B + R_{to}[2l] := R_{to}[2l] - main\_borrow - q$</span>
                - <span style="color:orange">2. $r_t := u - temp\_borrow$</span>
- <span style="color:orange">5.</span> $S_t := S L + Q$
    - <span style="color:orange">1.</span> $S_t := S_p L + Q$
        - $\iff S_t := S_pL + qL + Q_o$<br>
          $= s_tN + S_{to} := (S_p + q)L + Q_o$<br>
          with $S_t =: s_tN + S_{to,high}L + Q_o = s_tN + S_{to}$
        - <span style="color:orange">1. $sH + S_{o,high} := S_p +q$</span>
            - $S_{o,high}$ as length $h$, because $S_o$ has length $h$ .
        - <span style="color:orange">2. $S_{to} := S_{o,high}L + Q_o$ </span>
            - $S_{to}$ as length $n = h + l$, because $S_{o,high}$ has length $h$ and $Q_o$ has length $l$.
    - We can only execute these statements after 3.2. , because until including 3.2. <br>
      $S_p$ (and not $S_p + q$) is still needed
      and $S_p$ is stored at memory which will become $S_{to}$ here.
- TODO
- <span style="color:orange">6.</span> correct return values:
    - 1\. if $R_t < 0$ then
    - <span style="color:orange">1. if $r_t < 0$ then</span>
        - <span style="color:orange">1.</span> $R := R_t + 2S_t - 1$
            - <span style="color:orange">1. $R_{tt} := R_t + 2S_t$</span>
            - <span style="color:orange">2. $R := R_{tt} - 1$</span>
        - <span style="color:orange">2.</span> $S := S_t - 1$
            - <span style="color:orange">1. $S := S_t - 1$</span>
    - <span style="color:orange">2. else</span>
        - if $R_t \ge 0$
        - <span style="color:orange">1. $R := R_t$</span>
        - <span style="color:orange">2. $S := S_t$</span>
