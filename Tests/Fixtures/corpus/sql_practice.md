# SQL practice
SELECT name FROM students JOIN enrollments USING (student_id);
LEFT JOIN keeps rows with no match.
GROUP BY course_id HAVING COUNT(*) > 20;