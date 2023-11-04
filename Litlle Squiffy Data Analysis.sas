/****** IMPORTING 'PRODUCTS' SHEET FROM 'Little_Squiffy' Dataset ******/


PROC IMPORT 
		DATAFILE="/home/u63538266/Nipunn_Personal/DP using SAS/Little_Squiffy.xlsx" 
		DBMS=XLSX OUT=little_squiffy_products REPLACE;
	SHEET="Products";
RUN;


/****** CHANGING THE DATA TYPE ******/

PROC CONTENTS DATA=little_squiffy_products;
RUN;

/* We need to change the data types for the following variables
1. Created At -- Date/Time
2. Updated At -- Date/Time
3. Variant ID -- Num
4. Published At -- Date/Time
5. Review Count -- Num
6. Product ID -- Num
*/
DATA ls_products;
	
	/* Convert character to numeric */
	SET little_squiffy_products;
	pos=INPUT(Position, BEST32.);
	prod_id=INPUT('Product Id'n, BEST32.);
	review_count=INPUT('Review Count'n, BEST32.);
	var_id=INPUT('Variant Id'n, BEST32.);
	compare_at=INPUT('Compare At Price'n, BEST32.);
	created_id=INPUT('Created At'n, IS8601DT.);
	upd_at=INPUT('Updated At'n, IS8601DT.);
	pub_at=INPUT('Published At'n, IS8601DT.);

	/* Drop original character variable */
	DROP Position 'Product Id'n 'Review Count'n 'Variant Id'n 'Created At'n 'Updated At'n 
		'Published At'n 'Compare At Price'n;

	/* Rename numeric variable to original name */
	RENAME pos = Position prod_id='Product Id'n review_count='Review Count'n var_id='Variant Id'n 
		compare_at='Compare At Price'n created_id='Created At'n upd_at='Updated At'n 
		pub_at='Published At'n;


RUN;

/* Converting selected columns to datetime and numeric strings*/
DATA ls_products;
	SET ls_products;
	FORMAT 'Created At'n DATETIME18.
		'Updated At'n DATETIME18.
		'Published At'n DATETIME18.
		'Shopify Id'n BEST32.
		'Product Id'n BEST32.
		'Variant Id'n BEST32.
		Position BEST32.;
RUN;


/****** LOOKING FOR MISSNG VALUES ******/


PROC MEANS DATA=ls_products NMISS;
RUN;

PROC FREQ DATA=ls_products;
	TABLES Taxable Position Available 'Requires Shipping'n 'Option 1 Name'n 
		'Option 1 Value'n Description 'Product Type'n Url Image 'Option 2 Name'n 
		'Option 2 Value'n 'Option 3 Name'n 'Option 3 Value'n / MISSING NOCUM;
RUN;

/* Columns to be removed:
description,
product type,
URL,
image,
Option 2 Name,
Option 2 Value,
Option 3 Name,
Option 3 Value*/
DATA ls_products;
	SET ls_products;
	DROP Description 'Product Type'n Url Image 'Option 2 Name'n 'Option 2 Value'n 
		'Option 3 Name'n 'Option 3 Value'n;
RUN;


/****** REMOVING DUPLICATE VALUES ******/


PROC SORT DATA=ls_products OUT=ls_products_new DUPOUT=ls_products_dup NODUPKEY;
	BY 'Variant Id'n 'Product Id'n 'Shopify Id'n;
RUN;


/****** CHECKING AND REMOVING INCONSISTENT DATA VALUES ******/

/*1. INCONCSITENT GRAMS VALUES*/

PROC FREQ DATA=ls_products_new;
	TABLES Grams;
RUN;

/* There are 24 values where weight of the products = 0 which may or may not be possible. We will investigate more with the variable 'Requires Shipping'*/
DATA grams_data;
	SET ls_products_new;
	KEEP Grams 'Requires Shipping'n;
	WHERE Grams = 0;

RUN;

/* It is not possible to ship products which have '0' grams as thier weight. So we will remove the records with grams = 0 and 'Requires shipping' = 'YES'  */

DATA ls_products_new;
    SET ls_products_new;
    IF NOT (Grams = 0 AND 'Requires shipping'n = 'YES');
RUN;


PROC FREQ DATA=ls_products_new;
	TABLES 'Option 1 Value'n;
RUN;

/*2. INCONCSITENT 'Option 1 Value' VALUES*/

PROC FREQ DATA=ls_products_new;
	TABLES 'Option 1 Value'n;
RUN;

/* Grouping incorrenct values to correct values */
DATA ls_products_new;
	SET ls_products_new;

	/* Change the values of 'Option 1 Value' column  */
	IF 'Option 1 Value'n='150x200cm' THEN
		'Option 1 Value'n='150cm x 200cm';

	IF 'Option 1 Value'n='30cm ‰ˆ' THEN
		'Option 1 Value'n='30cm ~';

	IF 'Option 1 Value'n='40cm ‰ˆ' THEN
		'Option 1 Value'n='40cm ~';

	IF 'Option 1 Value'n='50cm ‰ˆ' THEN
		'Option 1 Value'n='50cm ~';

	IF 'Option 1 Value'n='70cm ‰ˆ' THEN
		'Option 1 Value'n='70cm ~';

	IF 'Option 1 Value'n='AU: Super King - 265x230cm' THEN
		'Option 1 Value'n='AU Super King - 265x230cm';
RUN;



/*** CREATING NEW SIMPLIFIED COLUMNS TO DETERMINE CATEGORIES OF THE PRODUCT ***/


/* Loading the frquency tables of 'Vendor' and 'Name' Variable */
PROC FREQ DATA=ls_products_new;
	TABLES Vendor Name;
RUN;

/*SIMILARITY ANALYSIS OF 'NAME' AND 'VENDOR' VARIABLE*/

/* We will calculate the similarity percentage of 'Vendor' and 'Name' Variable using Levenshtein distance */
DATA similarity_data;
    SET ls_products_new;

    /* Levenshtein distance */
    lev_distance = COMPLEV(Vendor, Name);

    /* Maximum possible distance */
    max_distance = MAX(LENGTH(Vendor), LENGTH(Name));

    /* similarity percentage */
    similarity_percentage = (1 - lev_distance / max_distance) * 100;
RUN;




PROC MEANS DATA=similarity_data;
	VAR similarity_percentage max_distance;
RUN;

/* THE MEAN VALUE OF SIMILARITY PERCENTAGE = 41.39% */

DATA length_string;
    SET similarity_data;
    length_of_vendor = LENGTH(Vendor);
    length_of_name = LENGTH(Name);

    /* Check which length is greater and assign a value to is_name_max */
    IF length_of_name >= length_of_vendor THEN is_name_max = 1; /* True */
    ELSE is_name_max = 0; /* False */
RUN;


PROC MEANS DATA=length_string;
	VAR is_name_max ;
RUN;

/* THE MEAN VALUE OF is_name_max = 1 WHICH MEANS THAT LENGHT(NAME) IS ALSWAYS GREATER THAN LENGHT(VENDOR) */




/* It is possible that Variable 'Name' consists of the name of the vendor in its record. So we will trim the name of the Vendor from 'Name' Variable and create a new column "Category" */
DATA ls_products_new;
	set ls_products_new;
	Category=tranwrd(Name, trim(Vendor), ' ');
RUN;

/* Checking the frequency distribution of 'Category' variable in descending order of count */
PROC FREQ DATA=ls_products_new ORDER=freq;
	TABLES Category ;
RUN;


/* We need to group the 'Category' columns based on the product type */

DATA ls_products_new;
	SET ls_products_new;

	/* Set length for NewColumn */
	LENGTH ProductType $ 60;


	IF INDEX(UPCASE(Category), 'BLANKET') > 0 THEN
		ProductType='Blanket';
		
	ELSE IF INDEX(UPCASE(Category), 'QUILT COVER SET') > 0 THEN
		ProductType='Quilt Cover Set';
		
	ELSE IF INDEX(UPCASE(Category), 'CURTAIN SET') > 0 THEN
		ProductType='Curtain Set';
		
	ELSE IF INDEX(UPCASE(Category), 'SHOWER CURTAIN') > 0 THEN
		ProductType='Shower Curtain';
		
	ELSE IF INDEX(UPCASE(Category), 'TAPESTRY') > 0 THEN
		ProductType='Tapestry';
		
	ELSE IF INDEX(UPCASE(Category), 'CUSHION COVER') > 0 THEN
		ProductType='Cushion Cover';
		
	ELSE IF INDEX(UPCASE(Category), 'PILLOW CASES') > 0 THEN
		ProductType='Pillow Cases';
		
	ELSE IF INDEX(UPCASE(Category), 'HOODIE') > 0 THEN
		ProductType='Hoodie';
		
	ELSE IF INDEX(UPCASE(Category), 'TOWEL') > 0 THEN
		ProductType='Towel';
		
	ELSE
		ProductType='Other';
RUN;

/* Checking the frequency distribution of 'ProductType' variable in descending order of count */
PROC FREQ DATA=ls_products_new  ORDER=freq;
	TABLES ProductType ;
RUN;

/* We have classified 97% of the data into 9 categories that we created  */


/*** CREATING DISCOUNT PERCENTAGE AND DISCOUNT COLUMNS ***/


DATA ls_products_new;
	SET ls_products_new;
	DiscountPercentage = ROUND((('Compare At Price'n - Price) / 'Compare At Price'n) * 100, 0.01);
	DiscountedPrice = Price - ((Price * DiscountPercentage)/100);
RUN;



/****** IMPORTING 'REVIEWS' SHEET FROM 'Little_Squiffy' Dataset ******/


PROC IMPORT 
	DATAFILE="/home/u63538266/Nipunn_Personal/DP using SAS/Little_Squiffy.xlsx" 
	DBMS=XLSX OUT=little_squiffy_reviews REPLACE;
SHEET="Reviews";
RUN;

PROC CONTENTS DATA=little_squiffy_reviews;
RUN;


/****** CHANGING THE DATA TYPE ******/


/* we need to change the data types for the following variables
1. Rating -- NUM
2. Thumbs Down Count -- NUM
*/
DATA ls_reviews;
	SET little_squiffy_reviews;
	rat=INPUT(Rating, BEST32.);
	td_count=INPUT('Thumb Down Count'n, BEST32.);
	
	DROP Rating 'Thumb Down Count'n;
	
	RENAME rat=Rating td_count='Thumb Down Count'n;
RUN;

/****** LOOKING FOR MISSNG VALUES ******/


PROC MEANS DATA=ls_reviews NMISS;
RUN;

PROC FREQ DATA=ls_reviews;
	TABLES Rating Reply 'Thumb Down Count'n 'Thumb Up Count'n Title/ MISSING NOCUM;
RUN;

/* Removing missing value Columns */
DATA ls_reviews;
	SET ls_reviews;
	DROP Reply 'Thumb Down Count'n 'Thumb Up Count'n;
RUN;


/****** REMOVING DUPLICATE VALUES ******/

PROC SORT DATA=ls_reviews OUT=ls_reviews_new DUPOUT=ls_reviews_dup NODUPKEY;
	BY 'Review Id'n;
RUN;

/****** MERGING 'PRODUCTS' SHEET amd 'REVIEWS' SHEET ******/

/* Ensure datasets are sorted by the key variable */
PROC SORT DATA=ls_products_new; 
    BY 'Product Id'n; 
RUN;

PROC SORT DATA=ls_reviews; 
    BY Product; 
RUN;

DATA merged_data;
    MERGE ls_products_new (RENAME=('Product Id'n=key) IN=a)
          ls_reviews (RENAME=(Product=key) IN=b);
    BY key;
RUN;


PROC SORT DATA=merged_data; 
    BY ProductType; 
RUN;







PROC CONTENTS data=merged_data;
RUN;


DATA merged_data;
	SET merged_data;
	FORMAT 
		Price BEST5.
		DiscountedPrice BEST5.
		DiscountPercentage BEST5.
		Rating BEST5.;
RUN;

ODS PDF FILE="/home/u63538266/Nipunn_Official/Assesment2_Report.pdf";

PROC MEANS DATA=merged_data NOPRINT;
    BY ProductType;
    VAR Price DiscountedPrice DiscountPercentage Rating;
    OUTPUT OUT=avg_data (DROP=_TYPE_ _FREQ_)
    	   N='Number of Products'n
           MEAN='Average Price'n 'Avererage Discounted Price'n 'Average Discount %'n 'Average Rating'n
           SUM('Review Count'n)='Number of Reviews'n;
RUN;


PROC MEANS DATA=merged_data NOPRINT MAXDEC=2;
    VAR Price DiscountedPrice DiscountPercentage Rating;
    OUTPUT OUT=overall_summary (DROP=_TYPE_ _FREQ_)
           N=TotalProductCount
           MEAN='Total Average Price'n 'Total Average Discounted Price'n 'Total Average Discount %'n 'Total Average Rating'n
           SUM('Review Count'n)='Total Reviews'n;
RUN;
/* 1. visualisation */

TITLE "DATA EXPLORATION AND ANALYSIS";
TITLE2 "Summary of Consolidated Table: Little Squiffy Products, Price, Reviews And Rating";
FOOTNOTE "'Blankets' and 'Quilt Cover Set' have the most number of items";
PROC PRINT DATA=avg_data ; 
RUN;
TITLE;
TITLE2;
FOOTNOTE;


TITLE "DATA EXPLORATION AND ANALYSIS";
TITLE2 "Overall Summary of Little Squiffy Products, Price, Reviews And Rating";
PROC PRINT DATA=overall_summary NOOBS ;
RUN;
TITLE;
TITLE2;

/* 2. visualisation */

TITLE "DATA EXPLORATION AND ANALYSIS";
Title2 "Price Distribution of Product Types of Little Squiffy ";

PROC SGPLOT DATA=merged_data;
    VBOX Price / CATEGORY=ProductType;
    XAXIS DISPLAY=(NOLABEL);
    YAXIS LABEL="Price (AUD)";
RUN;

DATA splitting;
    SET merged_data;
    pub_month_num = MONTH(DATEPART('Published At'n)); /* Numerical representation of month */
    pub_month = PUT(DATEPART('Published At'n), MONNAME.);
    pub_year = YEAR(DATEPART('Published At'n));
    pub_month_year = PUT(DATEPART('Published At'n), MONYY7.);
RUN;

/* 3. visualisation */

PROC SORT data=splitting;
    BY pub_year pub_month_num;
RUN;

PROC MEANS DATA=splitting NOPRINT;
    BY pub_year pub_month_num pub_month pub_month_year ;
    OUTPUT OUT=pub_data (DROP=_TYPE_ _FREQ_) N=Count_Products;
RUN;


PROC SGPLOT DATA=pub_data;
    SERIES X=pub_month_year Y=Count_Products / LINEATTRS=(COLOR=blue THICKNESS=1) DATALABEL DATALABELATTRS=(SIZE=5);
    REFLINE 400 / AXIS=Y LINEATTRS=(COLOR=red THICKNESS=2);
    XAXIS LABEL="Date" VALUEATTRS=(SIZE=5);  
    YAXIS LABEL="Number of Products Launched" GRID;
TITLE "DATA EXPLORATION AND ANALYSIS";
TITLE2 "Number of Products Launched (May2019 - Jan2023)";
FOOTNOTE "In 2020 & 2021, a large number of products are launched in winter season (Apr-July)";
RUN;
TITLE;
TITLE2;
FOOTNOTE;

/* 4. visualisation */

TITLE "EXPLORATORY DATA ANALYSIS";
TITLE2 "Relationship between 'Price' and 'Discounted Price'";

PROC CORR DATA=merged_data NOSIMPLE;
    VAR DiscountedPrice Price;
RUN;
TITLE;
TITLE2;



TITLE "EXPLORATORY DATA ANALYSIS";
TITLE2 "Relationship between 'Price' and 'Discounted Price'";
FOOTNOTE "Correlation Value: 0.99";
PROC SGPLOT DATA=merged_data;
    SCATTER Y=DiscountedPrice X=Price / MARKERATTRS=(SIZE=5 COLOR=black) TRANSPARENCY=0.5;
    REG X=Price Y=DiscountedPrice / DEGREE=1 LINEATTRS=(COLOR=MAGENTA); 
    YAXIS GRID LABELATTRS=(SIZE=9); 
    XAXIS GRID LABEL="Price (AUD)";
RUN;
TITLE;
TITLE2;
FOOTNOTE;


/* 5. visualisation */

TITLE "DATA EXPLORATION AND ANALYSIS";
TITLE2 "Average Discount Percentage by Number of Reviews";
FOOTNOTE "Significant Drop at 10 Reviews: Discount Percentage drops drastically to around 3.8%";
FOOTNOTE2"Well-reviewed products do not need hefty discounts to attract customers";
PROC SGPLOT DATA=merged_data;
    VBAR 'Review Count'n / RESPONSE=DiscountPercentage STAT=mean DATALABEL;
    WHERE DiscountPercentage >= 0;
    YAXIS LABEL="Discount %" GRID;
    XAXIS LABEL="Number of Reviews" GRID;
RUN;
TITLE;
TITLE2;
FOOTNOTE;
FOOTNOTE2;




/* 6. visualisation */

TITLE "DATA EXPLORATION AND ANALYSIS" ; 
TITLE2 "Are more expensive or premium products given prime positions?";
FOOTNOTE "Positive Correlation: Products placed further down the line might be more expensive on average";

PROC SGPLOT DATA=merged_data;
    SCATTER X=Position Y=Price / MARKERATTRS=(SIZE=5) TRANSPARENCY=0.5;
    REG Y=Price X=Position / DEGREE=1 LINEATTRS=(COLOR=RED); 
    YAXIS GRID LABEL="Price (AUD)" LABELATTRS=(SIZE=9); 
    XAXIS GRID;
RUN;
FOOTNOTE;
TITLE2;
TITLE;

/* 7. visualisation */

TITLE "DATA EXPLORATION AND ANALYSIS";
TITLE2 "Are discounted products placed higher to move inventory faster?";
FOOTNOTE "Negative Correlation: Products placed further down are less likely to have higher discounts; discounted products might be placed higher to facilitate quicker sales";
PROC SGPLOT DATA=merged_data;
    SCATTER X=Position Y=DiscountPercentage / MARKERATTRS=(SIZE=5) TRANSPARENCY=0.5;
    REG Y=DiscountPercentage X=Position / DEGREE=1 LINEATTRS=(COLOR=RED); /* Linear regression trendline */
    XAXIS GRID;
    YAXIS GRID LABEL="Discount %" LABELATTRS=(SIZE=9);
    WHERE DiscountPercentage >= 0;
RUN;
TITLE;
TITLE2;
FOOTNOTE;


ODS PDF CLOSE;

